import { Hono } from 'hono';
import { z } from 'zod';
import type { MercuryConfigurationCompiler } from '../../management/compiler.ts';
import { isManagementError, ManagementError } from '../../management/errors.ts';
import type { ManagementService } from '../../management/service.ts';
import {
  type AuthenticatedPrincipal,
  type EndpointTarget,
  type LandscapeTopology,
  MAX_MANAGEMENT_REQUEST_BYTES,
  type Quota,
  type ReplayScope,
} from '../../management/types.ts';

interface ManagementCompilationBinding {
  compiler: MercuryConfigurationCompiler;
  localLandscape: string;
  topology: LandscapeTopology;
}

export interface ManagementApiOptions {
  compilation?: ManagementCompilationBinding;
}

type ManagementVariables = {
  Variables: {
    principal: AuthenticatedPrincipal;
  };
};

const quotaSchema = z.object({
  intakeRps: z.number().int().positive(),
  burst: z.number().int().positive(),
  managementRps: z.number().int().positive(),
  retryWindowSeconds: z.number().int().positive(),
  dedupWindowSeconds: z.number().int().positive(),
  retentionMonths: z.number().int().positive(),
});

const endpointTargetSchema = z.discriminatedUnion('kind', [
  z
    .object({
      kind: z.literal('url'),
      url: z.string(),
    })
    .strict(),
  z
    .object({
      kind: z.literal('coordinate'),
      service: z.string(),
      module: z.string(),
      canonicalVlandscape: z.string(),
    })
    .strict(),
]);

async function readBoundedBody(request: Request): Promise<string> {
  const declaredLength = Number(request.headers.get('content-length') ?? '0');
  if (Number.isFinite(declaredLength) && declaredLength > MAX_MANAGEMENT_REQUEST_BYTES) {
    throw new ManagementError('invalid', 'management request body exceeds hard byte limit');
  }
  if (request.body === null) return '';

  const reader = request.body.getReader();
  const decoder = new TextDecoder();
  let byteLength = 0;
  let body = '';
  try {
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      byteLength += chunk.value.byteLength;
      if (byteLength > MAX_MANAGEMENT_REQUEST_BYTES) {
        try {
          await reader.cancel('management request body exceeds hard byte limit');
        } catch {
          // The size violation remains authoritative if cancellation itself fails.
        }
        throw new ManagementError('invalid', 'management request body exceeds hard byte limit');
      }
      body += decoder.decode(chunk.value, { stream: true });
    }
    body += decoder.decode();
    return body;
  } finally {
    reader.releaseLock();
  }
}

async function parseBody<T>(request: Request, schema: z.ZodType<T>): Promise<T> {
  let input: unknown;
  try {
    const body = await readBoundedBody(request);
    input = JSON.parse(body);
  } catch (error) {
    if (isManagementError(error)) throw error;
    throw new ManagementError('invalid', 'request body must be JSON');
  }
  const parsed = schema.safeParse(input);
  if (!parsed.success) {
    throw new ManagementError('invalid', 'request body is invalid', {
      issues: parsed.error.issues,
    });
  }
  return parsed.data;
}

async function rejectCompileTopologyBody(request: Request): Promise<void> {
  const body = await readBoundedBody(request);
  if (body.trim() === '') {
    return;
  }
  let input: unknown;
  try {
    input = JSON.parse(body);
  } catch {
    throw new ManagementError('invalid', 'compile trigger body must be empty JSON');
  }
  const parsed = z.object({}).strict().safeParse(input);
  if (!parsed.success) {
    throw new ManagementError(
      'invalid',
      'compile topology is trusted server configuration and cannot be supplied by a caller',
    );
  }
}

async function rejectDomainVerificationAssertion(request: Request): Promise<void> {
  const body = await readBoundedBody(request);
  if (body.trim() === '') return;
  let input: unknown;
  try {
    input = JSON.parse(body);
  } catch {
    throw new ManagementError('invalid', 'domain verification body must be empty JSON');
  }
  if (!z.object({}).strict().safeParse(input).success) {
    throw new ManagementError('invalid', 'domain verification success is server-derived and cannot be supplied');
  }
}

function statusForError(code: ManagementError['code']): 400 | 401 | 403 | 404 | 409 | 429 | 500 | 503 {
  switch (code) {
    case 'unauthorized':
      return 401;
    case 'forbidden':
      return 403;
    case 'not_found':
      return 404;
    case 'conflict':
    case 'immutable_home':
      return 409;
    case 'invalid':
      return 400;
    case 'rate_limited':
      return 429;
    case 'unavailable':
      return 503;
    case 'compiler_failed':
      return 500;
  }
}

export function createManagementApi(
  service: ManagementService,
  options: ManagementApiOptions = {},
): Hono<ManagementVariables> {
  const compilation =
    options.compilation === undefined
      ? undefined
      : {
          compiler: options.compilation.compiler,
          localLandscape: options.compilation.localLandscape,
          topology: structuredClone(options.compilation.topology),
        };
  if (
    compilation !== undefined &&
    (compilation.topology.landscapes.length !== 1 || compilation.topology.landscapes[0] !== compilation.localLandscape)
  ) {
    throw new ManagementError(
      'invalid',
      'trusted compilation topology must contain exactly the configured local landscape',
    );
  }
  const app = new Hono<ManagementVariables>();

  app.onError((error, context) => {
    if (isManagementError(error)) {
      if (error.code === 'unauthorized') {
        context.header('WWW-Authenticate', 'Bearer realm="mercury-management"');
      }
      return context.json(
        {
          error: error.code,
          message: error.message,
          details: error.details,
        },
        statusForError(error.code),
      );
    }
    return context.json({ error: 'internal', message: 'internal management API error' }, 500);
  });

  app.use('*', async (context, next) => {
    if (context.req.path === '/health') {
      await next();
      return;
    }
    const principal = await service.authenticateBearer(context.req.header('Authorization'));
    await service.consumeManagementRequest(principal);
    context.set('principal', principal);
    await next();
  });

  app.get('/health', async context => {
    const health = await service.health();
    return context.json(health, health.repository === 'ok' ? 200 : 503);
  });

  app.get('/accounts', async context => {
    const principal = context.get('principal');
    service.requireScope(principal, 'accounts:read');
    if (principal.scopes.includes('*') || principal.scopes.includes('accounts:all')) {
      return context.json({
        accounts: await service.repository.listAccounts(),
      });
    }
    return context.json({
      accounts: [await service.getAccountFor(principal, principal.accountId)],
    });
  });

  app.post('/accounts', async context => {
    const principal = context.get('principal');
    service.requireScope(principal, 'accounts:write');
    const input = await parseBody(
      context.req.raw,
      z.object({
        name: z.string(),
        kind: z.enum(['internal', 'external']),
      }),
    );
    return context.json(await service.createAccount(input), 201);
  });

  app.get('/accounts/:accountId', async context => {
    const principal = context.get('principal');
    service.requireScope(principal, 'accounts:read');
    return context.json(await service.getAccountFor(principal, context.req.param('accountId')));
  });

  app.post('/accounts/:accountId/credentials/rotate', async context => {
    const input = await parseBody(
      context.req.raw,
      z.object({
        tenantId: z.string().optional(),
        scopes: z.array(z.string()).optional(),
        overlapSeconds: z.number().int().positive().optional(),
      }),
    );
    return context.json(
      await service.rotateManagementCredential(context.get('principal'), context.req.param('accountId'), input),
      201,
    );
  });

  app.get('/tenants', async context => {
    const principal = context.get('principal');
    service.requireScope(principal, 'tenants:read');
    if (principal.tenantId !== undefined) {
      const tenant = await service.assertTenantAccess(principal, principal.tenantId);
      return context.json({ tenants: [tenant] });
    }
    const accountId =
      principal.scopes.includes('*') || principal.scopes.includes('accounts:all')
        ? context.req.query('accountId')
        : principal.accountId;
    return context.json({
      tenants: await service.repository.listTenants(accountId),
    });
  });

  app.post('/tenants', async context => {
    const principal = context.get('principal');
    service.requireScope(principal, 'tenants:write');
    const input = await parseBody(
      context.req.raw,
      z.object({
        accountId: z.string(),
        name: z.string(),
        intakeSlug: z.string(),
        source: z.enum(['api', 'cr']),
        homeVlandscape: z.string(),
        quota: quotaSchema.optional(),
      }),
    );
    await service.getAccountFor(principal, input.accountId);
    return context.json(await service.createOrAdoptTenant(input), 201);
  });

  app.get('/tenants/:tenantId', async context => {
    const principal = context.get('principal');
    service.requireScope(principal, 'tenants:read');
    const tenant = await service.assertTenantAccess(principal, context.req.param('tenantId'));
    const quota = await service.repository.getQuota(tenant.id);
    const metering = await service.repository.getMeteringConfiguration(tenant.id);
    return context.json({ tenant, quota, metering });
  });

  app.patch('/tenants/:tenantId', async context => {
    const principal = context.get('principal');
    service.requireScope(principal, 'tenants:write');
    const input = await parseBody(
      context.req.raw,
      z
        .object({
          homeVlandscape: z.string().optional(),
          intakeSlug: z.string().optional(),
        })
        .refine(value => value.homeVlandscape !== undefined || value.intakeSlug !== undefined, {
          message: 'an immutable identity field is required',
        }),
    );
    return context.json(await service.rejectIdentityChange(principal, context.req.param('tenantId'), input));
  });

  app.delete('/tenants/:tenantId', async context => {
    await service.deleteTenant(context.get('principal'), context.req.param('tenantId'));
    return context.body(null, 204);
  });

  app.put('/tenants/:tenantId/quota', async context => {
    const input = await parseBody(context.req.raw, quotaSchema);
    return context.json(
      await service.setQuota(
        context.get('principal'),
        context.req.param('tenantId'),
        input as Omit<Quota, 'tenantId' | 'updatedAt'>,
      ),
    );
  });

  app.put('/tenants/:tenantId/metering', async context => {
    const input = await parseBody(
      context.req.raw,
      z.object({
        enabled: z.boolean(),
        exportIntervalSeconds: z.number().int().positive(),
        dimensions: z.array(z.string()).min(1),
        billingAccountReference: z.string().optional(),
      }),
    );
    return context.json(
      await service.setMeteringConfiguration(context.get('principal'), context.req.param('tenantId'), input),
    );
  });

  app.post('/tenants/:tenantId/provider-credentials', async context => {
    const input = await parseBody(
      context.req.raw,
      z
        .object({
          credentialId: z.string(),
        })
        .strict(),
    );
    const { secretPointer: _secretPointer, ...credential } = await service.getProviderCredentialFor(
      context.get('principal'),
      context.req.param('tenantId'),
      input.credentialId,
    );
    return context.json(credential);
  });

  app.post('/admin/tenants/:tenantId/provider-credentials', async context => {
    const input = await parseBody(
      context.req.raw,
      z
        .object({
          provider: z.string(),
          secretPointer: z.string(),
        })
        .strict(),
    );
    const { secretPointer: _secretPointer, ...credential } = await service.registerProviderCredential(
      context.get('principal'),
      context.req.param('tenantId'),
      input,
    );
    return context.json(credential, 201);
  });

  app.post('/admin/tenants/:tenantId/endpoint-signing-credentials', async context => {
    const input = await parseBody(
      context.req.raw,
      z
        .object({
          endpointId: z.string().uuid(),
          secretPointer: z.string(),
        })
        .strict(),
    );
    const { secretPointer: _secretPointer, ...credential } = await service.registerEndpointSigningCredential(
      context.get('principal'),
      context.req.param('tenantId'),
      input,
    );
    return context.json(credential, 201);
  });

  app.get('/tenants/:tenantId/domains', async context => {
    const principal = context.get('principal');
    service.requireScope(principal, 'domains:read');
    const tenantId = context.req.param('tenantId');
    await service.assertTenantAccess(principal, tenantId);
    const domains = (await service.repository.listCustomDomains(tenantId)).map(
      ({ certificateSecretPointer: _certificate, verificationTokenHash: _tokenHash, ...domain }) => domain,
    );
    return context.json({ domains });
  });

  app.post('/tenants/:tenantId/domains', async context => {
    const input = await parseBody(
      context.req.raw,
      z
        .object({
          hostname: z.string(),
        })
        .strict(),
    );
    const registration = await service.registerCustomDomain(
      context.get('principal'),
      context.req.param('tenantId'),
      input,
    );
    const {
      certificateSecretPointer: _certificate,
      verificationTokenHash: _tokenHash,
      ...domain
    } = registration.domain;
    return context.json({ domain, records: registration.records }, 201);
  });

  app.post('/tenants/:tenantId/domains/:domainId/verify', async context => {
    await rejectDomainVerificationAssertion(context.req.raw);
    const {
      certificateSecretPointer: _certificate,
      verificationTokenHash: _tokenHash,
      ...domain
    } = await service.verifyCustomDomain(
      context.get('principal'),
      context.req.param('tenantId'),
      context.req.param('domainId'),
    );
    return context.json(domain);
  });

  app.delete('/tenants/:tenantId/domains/:domainId', async context => {
    await service.deleteCustomDomain(
      context.get('principal'),
      context.req.param('tenantId'),
      context.req.param('domainId'),
    );
    return context.body(null, 204);
  });

  app.get('/tenants/:tenantId/routes', async context => {
    const principal = context.get('principal');
    service.requireScope(principal, 'routes:read');
    const tenantId = context.req.param('tenantId');
    await service.assertTenantAccess(principal, tenantId);
    const registrations = [];
    for (const route of await service.repository.listRoutes(tenantId)) {
      registrations.push({
        route,
        endpoints: await service.repository.listEndpoints(route.id),
      });
    }
    return context.json({ routes: registrations });
  });

  app.post('/tenants/:tenantId/routes', async context => {
    const input = await parseBody(
      context.req.raw,
      z
        .object({
          id: z.string().optional(),
          path: z.string(),
          registeredUrl: z.string(),
          provider: z.string(),
          scheme: z.string().optional(),
          providerCredentialId: z.string().optional(),
        })
        .strict(),
    );
    return context.json(await service.upsertRoute(context.get('principal'), context.req.param('tenantId'), input), 201);
  });

  app.post('/tenants/:tenantId/routes/:routeId/endpoints', async context => {
    const input = await parseBody(
      context.req.raw,
      z
        .object({
          id: z.string().optional(),
          target: endpointTargetSchema,
          signingCredentialId: z.string(),
        })
        .strict(),
    );
    return context.json(
      await service.upsertEndpoint(
        context.get('principal'),
        context.req.param('tenantId'),
        context.req.param('routeId'),
        {
          ...input,
          target: input.target as EndpointTarget,
        },
      ),
      201,
    );
  });

  app.delete('/tenants/:tenantId/routes/:routeId', async context => {
    await service.deleteRoute(context.get('principal'), context.req.param('tenantId'), context.req.param('routeId'));
    return context.body(null, 204);
  });

  app.delete('/tenants/:tenantId/routes/:routeId/endpoints/:endpointId', async context => {
    await service.deleteEndpoint(
      context.get('principal'),
      context.req.param('tenantId'),
      context.req.param('routeId'),
      context.req.param('endpointId'),
    );
    return context.body(null, 204);
  });

  app.post('/tenants/:tenantId/subscriptions', async context => {
    const input = await parseBody(
      context.req.raw,
      z.object({
        id: z.string().optional(),
        provider: z.string(),
        externalId: z.string(),
        retentionSeconds: z.number().int().positive().optional(),
        deadLetterTarget: z.string().optional(),
        metadata: z.record(z.string(), z.unknown()).optional(),
      }),
    );
    return context.json(
      await service.registerSubscription(context.get('principal'), context.req.param('tenantId'), input),
      201,
    );
  });

  app.get('/landscapes', async context => {
    const principal = context.get('principal');
    service.requireScope(principal, 'landscapes:read');
    return context.json({
      landscapes: await service.repository.listLandscapeEventSources(principal.accountId),
    });
  });

  app.put('/landscapes/:landscape', async context => {
    const input = await parseBody(
      context.req.raw,
      z.object({
        queryUrl: z.string(),
        replayUrl: z.string(),
        credentialPointer: z.string(),
        enabled: z.boolean(),
      }),
    );
    return context.json(
      await service.saveLandscapeEventSource(context.get('principal'), {
        landscape: context.req.param('landscape'),
        ...input,
      }),
    );
  });

  app.post('/replays', async context => {
    const input = await parseBody(
      context.req.raw,
      z.object({
        tenantId: z.string(),
        landscape: z.string(),
        reason: z.string().min(1),
        scope: z.discriminatedUnion('kind', [
          z.object({ kind: z.literal('event'), eventId: z.string() }),
          z.object({ kind: z.literal('endpoint'), endpointId: z.string() }),
        ]),
      }),
    );
    return context.json(
      await service.requestReplay(context.get('principal'), {
        ...input,
        scope: input.scope as ReplayScope,
      }),
      202,
    );
  });

  app.post('/circuits/:endpointId/reenable', async context => {
    const input = await parseBody(context.req.raw, z.object({ tenantId: z.string(), landscape: z.string() }));
    return context.json(
      await service.reenableCircuit(context.get('principal'), {
        ...input,
        endpointId: context.req.param('endpointId'),
      }),
    );
  });

  app.post('/circuits/:endpointId/probe', async context => {
    const input = await parseBody(context.req.raw, z.object({ tenantId: z.string(), landscape: z.string() }));
    return context.json(
      await service.probeCircuit(context.get('principal'), {
        ...input,
        endpointId: context.req.param('endpointId'),
      }),
    );
  });

  app.get('/config/generations', async context => {
    const principal = context.get('principal');
    service.requireScope(principal, 'config:read');
    const landscape = context.req.query('landscape');
    const acknowledgements = await service.repository.listLandscapeAcknowledgements();
    return context.json({
      generations: await service.repository.listConfigGenerations(landscape),
      acknowledgements:
        landscape === undefined
          ? acknowledgements
          : acknowledgements.filter(acknowledgement => acknowledgement.landscape === landscape),
    });
  });

  app.post('/config/compile', async context => {
    const principal = context.get('principal');
    service.requireScope(principal, 'config:write');
    if (compilation === undefined) {
      throw new ManagementError('unavailable', 'compiler is not configured');
    }
    await rejectCompileTopologyBody(context.req.raw);
    const result = await compilation.compiler.compileAndPublish(compilation.topology);
    return context.json(
      {
        generation: result.generation,
        acknowledgedLandscapes: result.acknowledgedLandscapes,
      },
      202,
    );
  });

  return app;
}
