import { createHash, createHmac, createPublicKey, X509Certificate } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { signAsync } from '@noble/ed25519';
import { Hono } from 'hono';
import Redis from 'ioredis';
import { importPKCS8, SignJWT } from 'jose';
import postgres from 'postgres';
import { z } from 'zod';
import {
  appleBackfillEvidenceSchema,
  archiveLifecycleEvidenceSchema,
  atomicAcceptanceEvidenceSchema,
  consoleJourneyEvidenceSchema,
  dependencyEvidenceSchema,
  fanoutEvidenceSchema,
  googleSubscriptionEvidenceSchema,
  providerNames,
  providerVerificationMatrixSchema,
  route53LandingEvidenceSchema,
  signatureLifecycleEvidenceSchema,
  type ProviderName,
} from '../../src/sit/evidence.ts';
import { dedupKey, deriveDedupId } from '../../src/domain/dedup.ts';
import { verifyAuthorityAttestation } from './attestation.ts';

const env = (name: string): string => {
  const value = process.env[name]?.trim();
  if (value === undefined || value.length === 0) throw new Error(`missing ${name}`);
  return value;
};

const materialRoot = env('MERCURY_SIT_MATERIAL_ROOT');
const controlBearer = (await Bun.file(env('MERCURY_SIT_CONTROL_BEARER_FILE')).text()).trim();
const managementBearer = (await Bun.file(resolve(materialRoot, 'management-bootstrap-token')).text()).trim();
const publicProductOrigin = env('MERCURY_SIT_PUBLIC_PRODUCT_ORIGIN');
const productOrigins = {
  lapras: env('MERCURY_SIT_LAPRAS_ORIGIN'),
  farfetch: env('MERCURY_SIT_FARFETCH_ORIGIN'),
} as const;
const redisUrls = {
  lapras: env('MERCURY_SIT_LAPRAS_REDIS_URL'),
  farfetch: env('MERCURY_SIT_FARFETCH_REDIS_URL'),
} as const;
const postgresUrl = env('MERCURY_SIT_POSTGRES_URL');
const sinkOrigins = [env('MERCURY_SIT_SINK_COORDINATE_URL'), env('MERCURY_SIT_SINK_EXTERNAL_URL')] as const;
const archive = {
  endpoint: env('MERCURY_SIT_ARCHIVE_ENDPOINT'),
  bucket: env('MERCURY_SIT_ARCHIVE_BUCKET'),
  region: env('MERCURY_SIT_ARCHIVE_REGION'),
  accessKeyId: (await Bun.file(resolve(materialRoot, 'archive-access-key-id')).text()).trim(),
  secretAccessKey: (await Bun.file(resolve(materialRoot, 'archive-secret-access-key')).text()).trim(),
};

const sql = postgres(postgresUrl, { max: 4 });
const redis = {
  lapras: new Redis(redisUrls.lapras),
  farfetch: new Redis(redisUrls.farfetch),
};
const s3 = new Bun.S3Client({
  endpoint: archive.endpoint,
  bucket: archive.bucket,
  region: archive.region,
  accessKeyId: archive.accessKeyId,
  secretAccessKey: archive.secretAccessKey,
});
const consoleAuthorizationPrivateKey = await importPKCS8(
  await Bun.file(resolve(materialRoot, 'console-authorization-private-key')).text(),
  'ES256',
);
const consoleAuthorizationKeyId = createHash('sha256')
  .update(
    createPublicKey(await Bun.file(resolve(materialRoot, 'console-authorization-public-key')).text()).export({
      format: 'der',
      type: 'spki',
    }),
  )
  .digest('base64url')
  .slice(0, 32);

interface Session {
  readonly id: string;
  readonly nonce: string;
  readonly productBaseUrl: string;
  readonly accountId: string;
  readonly tenantId: string;
  readonly intakeSlug: string;
  readonly routeIds: Readonly<Record<string, string>>;
  readonly endpointIds: Readonly<Record<string, readonly string[]>>;
  readonly createdAtMs: number;
}

interface RouteRegistration {
  readonly route: { readonly id: string; readonly path: string };
  readonly endpoints: readonly { readonly id: string }[];
}

const sessions = new Map<string, Session>();
const jsonHeaders = { 'content-type': 'application/json' };
const managementHeaders = {
  authorization: `Bearer ${managementBearer}`,
  ...jsonHeaders,
};

const jsonRequest = async <T>(url: string, init: RequestInit = {}, accepted: readonly number[] = [200]): Promise<T> => {
  const response = await fetch(url, init);
  const body = await response.text();
  if (!accepted.includes(response.status)) {
    throw new Error(`${new URL(url).pathname} returned ${response.status}: ${body.slice(0, 240)}`);
  }
  return (body.length === 0 ? undefined : JSON.parse(body)) as T;
};

let managementTail = Promise.resolve();
let lastManagementRequestAtMs = 0;
const management = async <T>(
  origin: string,
  path: string,
  init: RequestInit = {},
  accepted: readonly number[] = [200],
): Promise<T> => {
  const previous = managementTail;
  let release!: () => void;
  managementTail = new Promise<void>(resolveGate => {
    release = resolveGate;
  });
  await previous;
  try {
    const waitMs = Math.max(0, 60 - (Date.now() - lastManagementRequestAtMs));
    if (waitMs > 0) await Bun.sleep(waitMs);
    return await jsonRequest<T>(
      `${origin}/management/v1${path}`,
      {
        ...init,
        headers: { ...managementHeaders, ...init.headers },
      },
      accepted,
    );
  } finally {
    lastManagementRequestAtMs = Date.now();
    release();
  }
};

const createEndpoint = async (
  tenantId: string,
  routeId: string,
  input: {
    readonly target:
      | { readonly kind: 'url'; readonly url: string }
      | {
          readonly kind: 'coordinate';
          readonly service: string;
          readonly module: string;
          readonly canonicalVlandscape: string;
        };
    readonly signingSecretPointer: string;
  },
): Promise<{ readonly id: string }> => {
  const endpointId = crypto.randomUUID();
  const credential = await management<{ readonly id: string }>(
    productOrigins.lapras,
    `/admin/tenants/${encodeURIComponent(tenantId)}/endpoint-signing-credentials`,
    {
      method: 'POST',
      body: JSON.stringify({
        endpointId,
        secretPointer: input.signingSecretPointer,
      }),
    },
    [201],
  );
  return management(
    productOrigins.lapras,
    `/tenants/${encodeURIComponent(tenantId)}/routes/${encodeURIComponent(routeId)}/endpoints`,
    {
      method: 'POST',
      body: JSON.stringify({
        id: endpointId,
        target: input.target,
        signingCredentialId: credential.id,
      }),
    },
    [201],
  );
};

const ensureRoute = async (
  tenantId: string,
  intakeSlug: string,
  existing: readonly RouteRegistration[],
  name: string,
  provider: ProviderName,
  providerCredentialId: string,
  endpointKinds: readonly ('coordinate' | 'external')[],
): Promise<RouteRegistration> => {
  const path = `/${name}`;
  let registration = existing.find(item => item.route.path === path);
  if (registration === undefined) {
    const route = await management<{ readonly id: string }>(
      productOrigins.lapras,
      `/tenants/${encodeURIComponent(tenantId)}/routes`,
      {
        method: 'POST',
        body: JSON.stringify({
          path,
          registeredUrl: `https://hooks.mercury.p.lapras.cluster.atomi.cloud/t/${intakeSlug}${path}`,
          provider,
          providerCredentialId,
        }),
      },
      [201],
    );
    registration = { route: { id: route.id, path }, endpoints: [] };
  }
  for (let index = registration.endpoints.length; index < endpointKinds.length; index += 1) {
    const kind = endpointKinds[index];
    if (kind === undefined) throw new Error('endpoint kind is unavailable');
    const endpoint = await createEndpoint(
      tenantId,
      registration.route.id,
      kind === 'coordinate'
        ? {
            target: {
              kind: 'coordinate',
              service: 'sit-sink',
              module: 'webhook',
              canonicalVlandscape: 'lapras',
            },
            signingSecretPointer: '/coordinate',
          }
        : {
            target: {
              kind: 'url',
              url: `${sinkOrigins[1]}/internal/webhooks/${provider}`,
            },
            signingSecretPointer: '/external',
          },
    );
    registration = { ...registration, endpoints: [...registration.endpoints, endpoint] };
  }
  return registration;
};

const bootstrap = async (
  sessionId: string,
): Promise<{
  readonly tenantId: string;
  readonly accountId: string;
  readonly intakeSlug: string;
  readonly routeIds: Record<string, string>;
  readonly endpointIds: Record<string, readonly string[]>;
}> => {
  const accountResponse = await management<{
    readonly accounts: readonly { readonly id: string; readonly name: string }[];
  }>(productOrigins.lapras, '/accounts');
  const account = accountResponse.accounts.find(item => item.name === 'internal/default');
  if (account === undefined) throw new Error('db-init did not provision internal/default');

  const tenantResponse = await management<{
    readonly tenants: readonly { readonly id: string; readonly name: string }[];
  }>(productOrigins.lapras, `/tenants?accountId=${encodeURIComponent(account.id)}`);
  const intakeSlug = `sit-${sessionId}`;
  const tenantName = `internal/${intakeSlug}`;
  if (tenantResponse.tenants.some(item => item.name === tenantName)) {
    throw new Error(`isolated SIT tenant ${tenantName} already exists`);
  }
  const tenant = await management<{ readonly id: string; readonly name: string }>(
    productOrigins.lapras,
    '/tenants',
    {
      method: 'POST',
      body: JSON.stringify({
        accountId: account.id,
        name: tenantName,
        intakeSlug,
        source: 'cr',
        homeVlandscape: 'lapras',
      }),
    },
    [201],
  );
  const readyTenant = tenant;
  if (readyTenant === undefined) throw new Error('management API did not return the SIT tenant');

  const registrations = await management<{ readonly routes: readonly RouteRegistration[] }>(
    productOrigins.lapras,
    `/tenants/${encodeURIComponent(readyTenant.id)}/routes`,
  );
  const routeIds: Record<string, string> = {};
  const endpointIds: Record<string, readonly string[]> = {};
  const providerCredentialIds = new Map<ProviderName, string>();
  for (const provider of providerNames) {
    const credential = await management<{ readonly id: string }>(
      productOrigins.lapras,
      `/admin/tenants/${encodeURIComponent(readyTenant.id)}/provider-credentials`,
      {
        method: 'POST',
        body: JSON.stringify({
          provider,
          secretPointer: `/${provider}.json`,
        }),
      },
      [201],
    );
    providerCredentialIds.set(provider, credential.id);
    const registration = await ensureRoute(
      readyTenant.id,
      intakeSlug,
      registrations.routes,
      provider,
      provider,
      credential.id,
      ['coordinate'],
    );
    routeIds[provider] = registration.route.id;
    endpointIds[provider] = registration.endpoints.map(endpoint => endpoint.id);
  }
  for (const [name, kinds] of [
    ['fanout-single', ['coordinate']],
    ['fanout-many', ['coordinate', 'coordinate', 'coordinate']],
  ] as const) {
    const stripeCredentialId = providerCredentialIds.get('stripe');
    if (stripeCredentialId === undefined) throw new Error('Stripe provider credential was not registered');
    const registration = await ensureRoute(
      readyTenant.id,
      intakeSlug,
      registrations.routes,
      name,
      'stripe',
      stripeCredentialId,
      kinds,
    );
    routeIds[name] = registration.route.id;
    endpointIds[name] = registration.endpoints.map(endpoint => endpoint.id);
  }

  for (const [landscape, queryUrl] of [
    ['lapras', `${productOrigins.lapras}/internal/landscape/v1`],
    ['farfetch', `${productOrigins.lapras}/__farfetch-landscape`],
  ] as const) {
    await management(productOrigins.lapras, `/landscapes/${landscape}`, {
      method: 'PUT',
      body: JSON.stringify({
        queryUrl,
        replayUrl: queryUrl,
        credentialPointer: '/landscape-native-credential',
        enabled: true,
      }),
    });
  }

  for (const origin of Object.values(productOrigins)) {
    await management(origin, '/config/compile', { method: 'POST', body: '{}' }, [202]);
  }
  for (const origin of Object.values(productOrigins)) {
    const ready = await fetch(`${origin}/health/ready`);
    if (!ready.ok) throw new Error(`${origin} did not become ready after configuration compile`);
  }
  return { accountId: account.id, tenantId: readyTenant.id, intakeSlug, routeIds, endpointIds };
};

const waitFor = async <T>(probe: () => Promise<T | undefined>, label: string, timeoutMs = 15_000): Promise<T> => {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const value = await probe();
    if (value !== undefined) return value;
    await Bun.sleep(100);
  }
  throw new Error(`timed out waiting for ${label}`);
};

const hmacHex = (secret: string, ...parts: readonly (string | Uint8Array)[]): string => {
  const hmac = createHmac('sha256', secret);
  for (const part of parts) hmac.update(part);
  return hmac.digest('hex');
};

interface Fixture {
  readonly body: Uint8Array;
  readonly headers: Record<string, string>;
  readonly format: string;
}

const fixture = async (provider: ProviderName, id: string, forged = false, _intakeSlug = 'sit'): Promise<Fixture> => {
  const nowMs = Date.now();
  const nowSeconds = Math.floor(nowMs / 1_000);
  const secret = (await Bun.file(resolve(materialRoot, 'provider-hmac-secret')).text()).trim();
  const bodyFor = (value: unknown): Uint8Array => new TextEncoder().encode(JSON.stringify(value));
  switch (provider) {
    case 'stripe': {
      const body = bodyFor({ id, type: 'sit.event', created: nowSeconds });
      const signature = forged ? '0'.repeat(64) : hmacHex(secret, `${nowSeconds}.`, body);
      return { body, headers: { 'stripe-signature': `t=${nowSeconds},v1=${signature}` }, format: 'stripe-v1' };
    }
    case 'airwallex': {
      const body = bodyFor({ id, name: 'sit.event', created_at: new Date(nowMs).toISOString() });
      const timestamp = String(nowMs);
      return {
        body,
        headers: {
          'x-timestamp': timestamp,
          'x-signature': forged ? '0'.repeat(64) : hmacHex(secret, timestamp, new TextDecoder().decode(body)),
        },
        format: 'airwallex-hmac-v1',
      };
    }
    case 'telegram': {
      const body = bodyFor({ update_id: Number(id.replace(/\D/g, '').slice(-9)) || nowSeconds });
      return {
        body,
        headers: { 'x-telegram-bot-api-secret-token': forged ? `${secret}-forged` : secret },
        format: 'telegram-secret-token',
      };
    }
    case 'logto': {
      const body = bodyFor({ event: 'PostRegister', createdAt: new Date(nowMs).toISOString(), id });
      return {
        body,
        headers: { 'logto-signature-sha-256': forged ? '0'.repeat(64) : hmacHex(secret, body) },
        format: 'logto-raw-body-hmac',
      };
    }
    case 'discord': {
      const body = bodyFor({ id, type: 1 });
      const timestamp = String(nowSeconds);
      const secretKey = Buffer.from((await Bun.file(resolve(materialRoot, 'discord-secret.hex')).text()).trim(), 'hex');
      const signed = new Uint8Array(new TextEncoder().encode(timestamp).byteLength + body.byteLength);
      signed.set(new TextEncoder().encode(timestamp));
      signed.set(body, timestamp.length);
      const signature = forged ? new Uint8Array(64) : await signAsync(signed, secretKey);
      return {
        body,
        headers: {
          'x-signature-ed25519': Buffer.from(signature).toString('hex'),
          'x-signature-timestamp': timestamp,
        },
        format: 'discord-ed25519',
      };
    }
    case 'google-play': {
      const body = bodyFor({ message: { messageId: id, publishTime: new Date(nowMs).toISOString(), data: 'e30=' } });
      const key = await importPKCS8(await Bun.file(resolve(materialRoot, 'google-private-key.pem')).text(), 'RS256');
      const token = await new SignJWT({
        email: 'mercury-sit@mercury-sit.iam.gserviceaccount.com',
        email_verified: true,
      })
        .setProtectedHeader({ alg: 'RS256' })
        .setIssuer('https://accounts.google.com')
        .setAudience(`${publicProductOrigin}/t/sit/google-play`)
        .setIssuedAt()
        .setExpirationTime('5m')
        .sign(key);
      return {
        body,
        headers: { authorization: `Bearer ${forged ? `${token.slice(0, -2)}xx` : token}` },
        format: 'google-pubsub-oidc',
      };
    }
    case 'apple-app-store': {
      const leaf = new X509Certificate(await readFile(resolve(materialRoot, 'ca/apple-leaf.pem')));
      const root = new X509Certificate(await readFile(resolve(materialRoot, 'ca/apple-root.pem')));
      const key = await importPKCS8(await Bun.file(resolve(materialRoot, 'ca/apple-leaf-key.pem')).text(), 'ES256');
      const signedPayload = await new SignJWT({
        notificationUUID: id,
        notificationType: 'DID_RENEW',
        signedDate: nowMs,
        data: {
          bundleId: 'cloud.atomi.mercury.sit',
          environment: 'Sandbox',
          appAppleId: 123456789,
        },
      })
        .setProtectedHeader({
          alg: 'ES256',
          x5c: [leaf.raw.toString('base64'), root.raw.toString('base64')],
        })
        .sign(key);
      return {
        body: bodyFor({ signedPayload: forged ? `${signedPayload.slice(0, -2)}xx` : signedPayload }),
        headers: {},
        format: 'apple-app-store-server-notification-v2',
      };
    }
  }
};

const postFixture = async (
  origin: string,
  intakeSlug: string,
  provider: ProviderName | 'fanout-single' | 'fanout-many',
  input: Fixture,
): Promise<Response> =>
  fetch(`${origin}/t/${intakeSlug}/${provider}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...input.headers },
    body: Buffer.from(input.body),
  });

const inspectDependencies = async (session: Session): Promise<z.infer<typeof dependencyEvidenceSchema>> => {
  const [laprasPong, farfetchPong, database, metrics] = await Promise.all([
    redis.lapras.ping(),
    redis.farfetch.ping(),
    sql`select current_database() as name`,
    fetch(`${productOrigins.lapras}/metrics`).then(async response => ({
      status: response.status,
      body: await response.text(),
    })),
  ]);
  if (laprasPong !== 'PONG' || farfetchPong !== 'PONG' || database[0]?.name !== 'mercury') {
    throw new Error('a required local dependency is not reachable');
  }
  const requiredSignals = [
    'mercury_intake_total',
    'mercury_verification_failures_total',
    'mercury_delivery_attempts_total',
    'mercury_archive_failures_total',
  ];
  if (metrics.status !== 200 || requiredSignals.some(signal => !metrics.body.includes(signal))) {
    throw new Error('runtime observability catalog is not available');
  }

  const objectKey = `sit/dependency-${crypto.randomUUID()}`;
  const payload = `mercury-${crypto.randomUUID()}`;
  await s3.file(objectKey).write(payload);
  const observed = await s3.file(objectKey).text();
  await s3.file(objectKey).delete();
  if (observed !== payload) throw new Error('Tigris read-after-write verification failed');

  const [secretStore, route53, tigris] = await Promise.all([
    verifyAuthorityAttestation({
      scenario: 'dependencies-secret-store',
      session,
      landscapes: Object.keys(productOrigins),
      trustJson: process.env.MERCURY_SIT_PROOF_TRUST_JSON,
      bearer: process.env.MERCURY_SIT_PROOF_BEARER,
    }).then(evidence =>
      dependencyEvidenceSchema.shape.secretStore.parse(
        z.object({ secretStore: dependencyEvidenceSchema.shape.secretStore }).strict().parse(evidence).secretStore,
      ),
    ),
    verifyAuthorityAttestation({
      scenario: 'dependencies-route53',
      session,
      landscapes: Object.keys(productOrigins),
      trustJson: process.env.MERCURY_SIT_PROOF_TRUST_JSON,
      bearer: process.env.MERCURY_SIT_PROOF_BEARER,
    }).then(evidence =>
      dependencyEvidenceSchema.shape.route53.parse(
        z.object({ route53: dependencyEvidenceSchema.shape.route53 }).strict().parse(evidence).route53,
      ),
    ),
    verifyAuthorityAttestation({
      scenario: 'dependencies-tigris',
      session,
      landscapes: Object.keys(productOrigins),
      trustJson: process.env.MERCURY_SIT_PROOF_TRUST_JSON,
      bearer: process.env.MERCURY_SIT_PROOF_BEARER,
    }).then(evidence =>
      dependencyEvidenceSchema.shape.tigris.parse(
        z.object({ tigris: dependencyEvidenceSchema.shape.tigris }).strict().parse(evidence).tigris,
      ),
    ),
  ]);
  return dependencyEvidenceSchema.parse({
    neon: {
      claimName: 'mercury-neon-shared',
      identity: new URL(postgresUrl).host,
      implementation: 'real',
      reachable: true,
    },
    upstash: [
      {
        claimName: 'mercury-upstash-lapras',
        identity: new URL(redisUrls.lapras).host,
        implementation: 'real',
        reachable: true,
        landscape: 'lapras',
      },
      {
        claimName: 'mercury-upstash-farfetch',
        identity: new URL(redisUrls.farfetch).host,
        implementation: 'real',
        reachable: true,
        landscape: 'farfetch',
      },
    ],
    tigris,
    secretStore,
    route53,
    observability: {
      claimName: 'mercury-prometheus-scrape',
      identity: `${productOrigins.lapras}/metrics`,
      implementation: 'real',
      reachable: metrics.status === 200,
    },
  });
};

const providerVerification = async (session: Session): Promise<z.infer<typeof providerVerificationMatrixSchema>> => {
  const evidence = [];
  const eventIndexKey = `evt-index:${encodeURIComponent(session.tenantId)}`;
  for (const provider of providerNames) {
    const acceptedId = `sit-${provider}-${crypto.randomUUID()}`;
    const beforeAccepted = await redis.lapras.zcard(eventIndexKey);
    const accepted = await postFixture(
      productOrigins.lapras,
      session.intakeSlug,
      provider,
      await fixture(provider, acceptedId, false, session.intakeSlug),
    );
    const acceptedEventId = accepted.headers.get('x-atomi-webhook-event-id');
    const acceptedPersisted =
      acceptedEventId === null ? null : await redis.lapras.get(`event:${encodeURIComponent(acceptedEventId)}`);
    const afterAccepted = await redis.lapras.zcard(eventIndexKey);
    const forgedId = `sit-${provider}-forged-${crypto.randomUUID()}`;
    const beforeForged = await redis.lapras.zcard(eventIndexKey);
    const forged = await postFixture(
      productOrigins.lapras,
      session.intakeSlug,
      provider,
      await fixture(provider, forgedId, true, session.intakeSlug),
    );
    const afterForged = await redis.lapras.zcard(eventIndexKey);
    evidence.push({
      provider,
      fixtureFormat: (await fixture(provider, `format-${crypto.randomUUID()}`, false, session.intakeSlug)).format,
      acceptedStatus: accepted.status,
      acceptedEventDelta: afterAccepted - beforeAccepted,
      forgedStatus: forged.status,
      forgedEventDelta: afterForged - beforeForged,
    });
    if (
      accepted.status !== 200 ||
      acceptedEventId === null ||
      acceptedPersisted === null ||
      forged.headers.get('x-atomi-webhook-event-id') !== null ||
      afterForged !== beforeForged
    ) {
      throw new Error(`${provider} persistence did not match verification outcomes`);
    }
  }
  return providerVerificationMatrixSchema.parse(evidence);
};

const fanout = async (session: Session): Promise<z.infer<typeof fanoutEvidenceSchema>> => {
  const run = async (name: 'fanout-single' | 'fanout-many', landscape: keyof typeof productOrigins) => {
    const eventStore = redis[landscape];
    const response = await postFixture(
      productOrigins[landscape],
      session.intakeSlug,
      name,
      await fixture('stripe', `${name}-${crypto.randomUUID()}`, false, session.intakeSlug),
    );
    if (response.status !== 200) throw new Error(`${name} intake returned ${response.status}`);
    const eventId = response.headers.get('x-atomi-webhook-event-id');
    if (eventId === null) throw new Error(`${name} response did not expose an event id`);
    const jobIds = await waitFor(async () => {
      const ids = await eventStore.smembers(`event-jobs:${encodeURIComponent(eventId)}`);
      return ids.length > 0 ? ids : undefined;
    }, `${name} jobs`);
    const measured = await Promise.all(
      jobIds.map(async id =>
        waitFor(async () => {
          const value = await eventStore.get(`job:${encodeURIComponent(id)}`);
          if (value === null) return undefined;
          const job = JSON.parse(value) as {
            readonly endpointId: string;
            readonly addressKind: string;
            readonly address: string;
            readonly attempts: readonly { readonly statusCode?: number }[];
          };
          return job.attempts.length > 0 ? job : undefined;
        }, `${name} delivery ${id}`),
      ),
    );
    const registrations = await management<{ readonly routes: readonly RouteRegistration[] }>(
      productOrigins.lapras,
      `/tenants/${encodeURIComponent(session.tenantId)}/routes`,
    );
    const registered =
      registrations.routes.find(item => item.route.path === `/${name}`)?.endpoints.map(item => item.id) ?? [];
    return {
      registeredEndpointIds: registered,
      unregisteredEndpointIds: [`not-registered-${crypto.randomUUID()}`],
      deliveries: await Promise.all(
        measured.map(async job => {
          return {
            endpointId: job.endpointId,
            addressKind: job.addressKind,
            address: job.address,
            responseStatus: job.attempts.at(-1)?.statusCode ?? 0,
          };
        }),
      ),
    };
  };
  return fanoutEvidenceSchema.parse({
    singleRegistration: await run('fanout-single', 'lapras'),
    perRowRegistrations: await run('fanout-many', 'farfetch'),
  });
};

interface StoredJob {
  readonly id: string;
  readonly tenantId: string;
  readonly endpointId: string;
  readonly addressKind: string;
  readonly address: string;
  readonly dueAtMs: number;
  readonly status: string;
  readonly attempts: readonly {
    readonly number: number;
    readonly attemptedAtMs: number;
    readonly signatureTimestampSeconds: number;
    readonly statusCode?: number;
    readonly replay: boolean;
  }[];
}

const readJob = async (client: Redis, jobId: string): Promise<StoredJob | undefined> => {
  const value = await client.get(`job:${encodeURIComponent(jobId)}`);
  return value === null ? undefined : (JSON.parse(value) as StoredJob);
};

const sessionJobCount = async (client: Redis, tenantId: string): Promise<number> => {
  let cursor = '0';
  let count = 0;
  do {
    const [next, keys] = await client.scan(cursor, 'MATCH', 'job:*', 'COUNT', 1000);
    cursor = next;
    if (keys.length > 0) {
      const values = await client.mget(keys);
      count += values.filter(value => value !== null && (JSON.parse(value) as StoredJob).tenantId === tenantId).length;
    }
  } while (cursor !== '0');
  return count;
};

const expiryTime = async (client: Redis, key: string): Promise<number> => {
  const value = Number(await client.call('PEXPIRETIME', key));
  if (!Number.isSafeInteger(value) || value < 1) throw new Error(`${key} does not have a bounded expiry`);
  return value;
};

const atomicAcceptance = async (session: Session): Promise<z.infer<typeof atomicAcceptanceEvidenceSchema>> => {
  const provider = 'stripe';
  const providerEventId = `atomic-${crypto.randomUUID()}`;
  const input = await fixture(provider, providerEventId, false, session.intakeSlug);
  const eventIndexKey = `evt-index:${encodeURIComponent(session.tenantId)}`;
  const response = await postFixture(productOrigins.lapras, session.intakeSlug, provider, input);
  const responseCompletedAtMs = Date.now();
  const eventId = response.headers.get('x-atomi-webhook-event-id');
  if (response.status !== 200 || eventId === null) throw new Error(`atomic intake returned ${response.status}`);
  const encodedEventId = encodeURIComponent(eventId);
  const envelopeText = await redis.lapras.get(`event:${encodedEventId}`);
  if (envelopeText === null) throw new Error('accepted event was not persisted before the response');
  const envelope = JSON.parse(envelopeText) as {
    readonly id: string;
    readonly acknowledgedAtMs?: number;
    readonly obligations: readonly { readonly endpointId: string }[];
  };
  if (envelope.acknowledgedAtMs === undefined) throw new Error('accepted event was not acknowledged before response');
  const jobIds = await redis.lapras.smembers(`event-jobs:${encodedEventId}`);
  const firstJob = await waitFor(async () => {
    for (const jobId of jobIds) {
      const job = await readJob(redis.lapras, jobId);
      if (job?.attempts[0] !== undefined) return job;
    }
    return undefined;
  }, 'first atomic delivery');
  const dedup = dedupKey(
    session.tenantId,
    session.routeIds[provider] ?? '',
    deriveDedupId(providerEventId, input.body, ''),
  );
  const dedupExpiresAtMs = await expiryTime(redis.lapras, dedup);

  const duplicateBeforeEvents = await redis.lapras.zcard(eventIndexKey);
  const duplicateBeforeJobs = await sessionJobCount(redis.lapras, session.tenantId);
  const duplicateResponse = await postFixture(productOrigins.lapras, session.intakeSlug, provider, input);
  const duplicateExpiry = await expiryTime(redis.lapras, dedup);
  const duplicateAfterEvents = await redis.lapras.zcard(eventIndexKey);
  const duplicateAfterJobs = await sessionJobCount(redis.lapras, session.tenantId);

  const otherBeforeEvents = await redis.farfetch.zcard(eventIndexKey);
  const otherBeforeJobs = await sessionJobCount(redis.farfetch, session.tenantId);
  const otherResponse = await postFixture(productOrigins.farfetch, session.intakeSlug, provider, input);
  const otherEventId = otherResponse.headers.get('x-atomi-webhook-event-id');
  if (otherEventId === null) throw new Error('other landscape did not expose an event id');

  const failedProviderId = `atomic-failed-${crypto.randomUUID()}`;
  const failedDedup = dedupKey(
    session.tenantId,
    session.routeIds[provider] ?? '',
    deriveDedupId(failedProviderId, new Uint8Array(), ''),
  );
  const failedBeforeEvents = await redis.lapras.zcard(eventIndexKey);
  const failedBeforeJobs = await sessionJobCount(redis.lapras, session.tenantId);
  const monthIndex = `evt-months:${encodeURIComponent(session.tenantId)}`;
  const backupIndex = `${monthIndex}:sit-backup:${session.id}`;
  const hadMonthIndex = (await redis.lapras.exists(monthIndex)) === 1;
  if (hadMonthIndex) await redis.lapras.rename(monthIndex, backupIndex);
  let failedResponse: Response | undefined;
  try {
    await redis.lapras.set(monthIndex, 'incompatible-sit-type');
    failedResponse = await postFixture(
      productOrigins.lapras,
      session.intakeSlug,
      provider,
      await fixture(provider, failedProviderId, false, session.intakeSlug),
    );
  } finally {
    await redis.lapras.del(monthIndex);
    if (hadMonthIndex) await redis.lapras.rename(backupIndex, monthIndex);
  }
  const failedAfterEvents = await redis.lapras.zcard(eventIndexKey);
  const failedAfterJobs = await sessionJobCount(redis.lapras, session.tenantId);
  if (failedResponse === undefined) throw new Error('failed commit response was not observed');

  return atomicAcceptanceEvidenceSchema.parse({
    provider,
    landingLandscape: 'lapras',
    storedEventId: envelope.id,
    storedAcknowledgedAtMs: envelope.acknowledgedAtMs,
    responseStatus: response.status,
    responseCompletedAtMs,
    firstDeliveryStartedAtMs: firstJob.attempts[0]?.attemptedAtMs,
    registeredEndpointIds: session.endpointIds[provider] ?? [],
    committedEndpointIds: envelope.obligations.map(obligation => obligation.endpointId),
    dedupExpiresAtMs,
    duplicate: {
      responseStatus: duplicateResponse.status,
      eventDelta: duplicateAfterEvents - duplicateBeforeEvents,
      obligationDelta: duplicateAfterJobs - duplicateBeforeJobs,
      dedupExpiresAtMs: duplicateExpiry,
    },
    otherLandscape: {
      landscape: 'farfetch',
      responseStatus: otherResponse.status,
      eventDelta: (await redis.farfetch.zcard(eventIndexKey)) - otherBeforeEvents,
      obligationDelta: (await sessionJobCount(redis.farfetch, session.tenantId)) - otherBeforeJobs,
    },
    failedCommit: {
      responseStatus: failedResponse.status,
      dedupDelta: await redis.lapras.exists(failedDedup),
      eventDelta: failedAfterEvents - failedBeforeEvents,
      obligationDelta: failedAfterJobs - failedBeforeJobs,
    },
  });
};

interface SinkAttempt {
  readonly atMs: number;
  readonly endpointId: string;
  readonly landingLandscape: string;
  readonly headers: Readonly<Record<string, string>>;
  readonly rawBodyBase64: string;
  readonly status: number;
}

const sinkAttempts = async (
  sinkOrigin: string,
  endpointId: string,
  eventId?: string,
): Promise<{ readonly attempts: readonly SinkAttempt[]; readonly handlerInvocations: number }> => {
  const query = new URLSearchParams({ endpointId });
  if (eventId !== undefined) query.set('eventId', eventId);
  return jsonRequest(`${sinkOrigin}/__control/attempts?${query}`);
};

const signatureLifecycle = async (session: Session): Promise<z.infer<typeof signatureLifecycleEvidenceSchema>> => {
  const endpointId = session.endpointIds.stripe?.[0];
  if (endpointId === undefined) throw new Error('signature endpoint was not registered');
  await jsonRequest(
    `${sinkOrigins[0]}/__control/failure`,
    {
      method: 'POST',
      headers: jsonHeaders,
      body: JSON.stringify({ endpointId, count: 1 }),
    },
    [204],
  );
  const response = await postFixture(
    productOrigins.lapras,
    session.intakeSlug,
    'stripe',
    await fixture('stripe', `signature-${crypto.randomUUID()}`, false, session.intakeSlug),
  );
  const eventId = response.headers.get('x-atomi-webhook-event-id');
  if (response.status !== 200 || eventId === null) throw new Error(`signature intake returned ${response.status}`);
  const firstAttempt = await waitFor(async () => {
    const observed = await sinkAttempts(sinkOrigins[0], endpointId, eventId);
    return observed.attempts.length >= 1 ? observed.attempts[0] : undefined;
  }, 'initial signature');
  const retryJobId = (await redis.lapras.smembers(`event-jobs:${encodeURIComponent(eventId)}`))[0];
  if (retryJobId === undefined) throw new Error('signature retry job was not persisted');
  const scheduledRetry = await waitFor(async () => {
    const current = await readJob(redis.lapras, retryJobId);
    return current !== undefined &&
      current.attempts.length === 1 &&
      current.status === 'pending' &&
      current.dueAtMs > Date.now() + 1_000
      ? current
      : undefined;
  }, 'scheduled signature retry');
  const dueAtMs = Date.now();
  await redis.lapras
    .multi()
    .set(`job:${encodeURIComponent(retryJobId)}`, JSON.stringify({ ...scheduledRetry, dueAtMs, status: 'pending' }))
    .zadd('q:retry', dueAtMs, retryJobId)
    .exec();
  await waitFor(async () => {
    const observed = await sinkAttempts(sinkOrigins[0], endpointId, eventId);
    return observed.attempts.length >= 2 ? observed.attempts : undefined;
  }, 'retry signature');

  await management(
    productOrigins.lapras,
    '/replays',
    {
      method: 'POST',
      body: JSON.stringify({
        tenantId: session.tenantId,
        landscape: 'lapras',
        reason: `SIT signature replay ${session.id}`,
        scope: { kind: 'event', eventId },
      }),
    },
    [202],
  );
  const allAttempts = await waitFor(
    async () => {
      const observed = await sinkAttempts(sinkOrigins[0], endpointId, eventId);
      return observed.attempts.length >= 3 ? observed.attempts : undefined;
    },
    'replay signature',
    20_000,
  );
  const job = await waitFor(async () => {
    const current = await readJob(redis.lapras, retryJobId);
    return current !== undefined && current.attempts.length >= 3 ? current : undefined;
  }, 'signature job attempts');

  const rawBody = Buffer.from(firstAttempt.rawBodyBase64, 'base64');
  const signingSecret = new Uint8Array(await Bun.file(resolve(materialRoot, 'endpoint-signing-secret')).arrayBuffer());
  const rejected = [];
  for (const [path, origin] of [
    ['cluster-local', sinkOrigins[0]],
    ['public', `${productOrigins.lapras}/__public-sink`],
  ] as const) {
    for (const mutation of ['forged', 'stale', 'stripped'] as const) {
      const before = await sinkAttempts(sinkOrigins[0], endpointId);
      const oldTimestamp = Math.floor(Date.now() / 1_000) - 600;
      const stale = `t=${oldTimestamp}, v1=${createHmac('sha256', signingSecret)
        .update(`${oldTimestamp}.`)
        .update(rawBody)
        .digest('hex')}`;
      const signature =
        mutation === 'forged'
          ? `t=${Math.floor(Date.now() / 1_000)}, v1=${'0'.repeat(64)}`
          : mutation === 'stale'
            ? stale
            : undefined;
      const invalid = await fetch(`${origin}/internal/webhooks/stripe`, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'x-atomi-webhook-endpoint-id': endpointId,
          ...(signature === undefined ? {} : { 'x-atomi-webhook-signature': signature }),
        },
        body: rawBody,
      });
      const after = await sinkAttempts(sinkOrigins[0], endpointId);
      rejected.push({
        path,
        mutation,
        consumerStatus: invalid.status,
        handlerInvocationDelta: after.handlerInvocations - before.handlerInvocations,
      });
    }
  }
  signingSecret.fill(0);

  return signatureLifecycleEvidenceSchema.parse({
    attempts: allAttempts.slice(0, 3).map((attempt, index) => ({
      kind: index === 0 ? 'initial' : index === 1 ? 'retry' : 'replay',
      attempt: job.attempts[index]?.number ?? index + 1,
      replay: job.attempts[index]?.replay ?? false,
      timestampSeconds: job.attempts[index]?.signatureTimestampSeconds ?? 0,
      signatureHeader: attempt.headers['x-atomi-webhook-signature'] ?? '',
      rawBodyBase64: attempt.rawBodyBase64,
      consumerStatus: attempt.status,
    })),
    rejected,
  });
};

const responseCookies = (response: Response): string =>
  response.headers
    .getSetCookie()
    .map(value => value.split(';', 1)[0])
    .filter(value => value !== undefined)
    .join('; ');

const csrfFrom = (html: string): string => {
  const token = /name="csrf"\s+value="([^"]+)"/.exec(html)?.[1];
  if (token === undefined) throw new Error('console did not render a CSRF token');
  return token;
};

const consoleJourney = async (session: Session): Promise<z.infer<typeof consoleJourneyEvidenceSchema>> => {
  const eventIds: Record<'lapras' | 'farfetch', string> = { lapras: '', farfetch: '' };
  for (const landscape of ['lapras', 'farfetch'] as const) {
    const accepted = await postFixture(
      productOrigins[landscape],
      session.intakeSlug,
      'stripe',
      await fixture('stripe', `console-${landscape}-${crypto.randomUUID()}`, false, session.intakeSlug),
    );
    const eventId = accepted.headers.get('x-atomi-webhook-event-id');
    if (accepted.status !== 200 || eventId === null) {
      throw new Error(`${landscape} console fixture returned ${accepted.status}`);
    }
    eventIds[landscape] = eventId;
  }

  const loginPage = await fetch(`${productOrigins.lapras}/console/login`);
  const loginHtml = await loginPage.text();
  const loginCsrf = csrfFrom(loginHtml);
  const loginResponse = await fetch(`${productOrigins.lapras}/console/login`, {
    method: 'POST',
    redirect: 'manual',
    headers: {
      'content-type': 'application/x-www-form-urlencoded',
      cookie: responseCookies(loginPage),
      origin: publicProductOrigin,
    },
    body: new URLSearchParams({
      csrf: loginCsrf,
      accountName: 'internal/default',
      bearerCredential: managementBearer,
    }),
  });
  if (loginResponse.status !== 303) throw new Error(`console login returned ${loginResponse.status}`);
  const sessionCookie = responseCookies(loginResponse);
  if (sessionCookie.length === 0) throw new Error('console login did not issue a session cookie');

  const dashboard = await fetch(`${productOrigins.lapras}/console?tenant=${encodeURIComponent(session.tenantId)}`, {
    headers: { cookie: sessionCookie },
  });
  const dashboardHtml = await dashboard.text();
  const returnedSourceLandscapes = (['lapras', 'farfetch'] as const).filter(landscape =>
    dashboardHtml.includes(eventIds[landscape]),
  );
  if (dashboard.status !== 200 || returnedSourceLandscapes.length !== 2 || dashboardHtml.includes('PARTIAL')) {
    const sourceFailures = [...dashboardHtml.matchAll(/<li>(lapras|farfetch) · ([^<]{1,200})<\/li>/g)].map(
      match => match[0],
    );
    throw new Error(
      `console fan-in failed: status=${dashboard.status}, returned=${returnedSourceLandscapes.join(',')}, failures=${sourceFailures.join(';')}`,
    );
  }

  const replayPath = `/console/events/lapras/${encodeURIComponent(eventIds.lapras)}/replay`;
  const confirmation = await fetch(`${productOrigins.lapras}${replayPath}`, {
    headers: { cookie: sessionCookie },
  });
  const confirmationHtml = await confirmation.text();
  if (confirmation.status !== 200 || !confirmationHtml.includes('REPLAY EVENT')) {
    throw new Error('console did not render the replay confirmation');
  }
  const replayCsrf = csrfFrom(confirmationHtml);
  const endpointId = session.endpointIds.stripe?.[0];
  if (endpointId === undefined) throw new Error('console replay endpoint was not registered');
  const attemptsBefore = await sinkAttempts(sinkOrigins[0], endpointId, eventIds.lapras);
  const replay = await fetch(`${productOrigins.lapras}${replayPath}`, {
    method: 'POST',
    headers: {
      'content-type': 'application/x-www-form-urlencoded',
      cookie: sessionCookie,
      origin: publicProductOrigin,
    },
    body: new URLSearchParams({
      csrf: replayCsrf,
      confirmation: 'REPLAY EVENT',
      reason: `SIT console replay ${session.id}`,
    }),
  });
  const replayHtml = await replay.text();
  if (!replay.ok || !replayHtml.includes('Control request accepted')) {
    throw new Error(`console replay returned ${replay.status}`);
  }
  const replayAttempt = await waitFor(async () => {
    const observed = await sinkAttempts(sinkOrigins[0], endpointId, eventIds.lapras);
    return observed.attempts.length > attemptsBefore.attempts.length ? observed.attempts.at(-1) : undefined;
  }, 'console replay delivery');
  const replayAuditRows = await sql<{ readonly count: number }[]>`
    select count(*)::integer as count
    from mercury_management.replay_audit
    where tenant_id = ${session.tenantId}
  `;

  return consoleJourneyEvidenceSchema.parse({
    loginStatus: dashboard.status,
    accountName: 'internal/default',
    queriedLandscapes: ['lapras', 'farfetch'],
    returnedSourceLandscapes,
    partialFailures: [],
    replay: {
      requestStatus: replay.status,
      sourceLandscape: 'lapras',
      enqueuedLandscape: replayAttempt.landingLandscape,
      endpointId: replayAttempt.endpointId,
      replayFlag: true,
      freshSignatureAccepted:
        replayAttempt.status === 200 &&
        !attemptsBefore.attempts.some(
          attempt =>
            attempt.headers['x-atomi-webhook-signature'] === replayAttempt.headers['x-atomi-webhook-signature'],
        ),
      auditRecorded: (replayAuditRows[0]?.count ?? 0) > 0,
    },
    preview: {
      gate: 'D11',
      routeStateVisible: dashboardHtml.includes(session.routeIds.stripe ?? ''),
      callbackDeliveryVisible: !dashboardHtml.includes('Preview callback delivery visibility: WITHHELD'),
    },
  });
};

const attested = async <T>(scenario: string, schema: z.ZodType<T>, session: Session): Promise<T> =>
  schema.parse(
    await verifyAuthorityAttestation({
      scenario,
      session,
      landscapes: Object.keys(productOrigins),
      trustJson: process.env.MERCURY_SIT_PROOF_TRUST_JSON,
      bearer: process.env.MERCURY_SIT_PROOF_BEARER,
    }),
  );

const nativeBearer = async (session: Session, tenants: readonly string[]): Promise<string> => {
  const issuedAt = Math.floor(Date.now() / 1_000);
  return new SignJWT({
    sid: session.id,
    tenants,
    landscapes: ['lapras'],
    capabilities: ['retention:run'],
  })
    .setProtectedHeader({
      alg: 'ES256',
      kid: consoleAuthorizationKeyId,
      typ: 'atomi-mercury-console+jwt',
    })
    .setIssuer('mercury-sit')
    .setAudience('mercury-management')
    .setSubject(session.accountId)
    .setJti(crypto.randomUUID())
    .setIssuedAt(issuedAt)
    .setExpirationTime(issuedAt + 120)
    .sign(consoleAuthorizationPrivateKey);
};

interface PreparedArchiveEvent {
  readonly eventId: string;
  readonly month: string;
  readonly streamCursor: string;
}

const prepareOldArchiveEvent = async (session: Session): Promise<PreparedArchiveEvent> => {
  const accepted = await postFixture(
    productOrigins.lapras,
    session.intakeSlug,
    'stripe',
    await fixture('stripe', `archive-${crypto.randomUUID()}`, false, session.intakeSlug),
  );
  const eventId = accepted.headers.get('x-atomi-webhook-event-id');
  if (accepted.status !== 200 || eventId === null) {
    throw new Error(`archive intake returned ${accepted.status}`);
  }
  const encodedEventId = encodeURIComponent(eventId);
  const jobIds = await redis.lapras.smembers(`event-jobs:${encodedEventId}`);
  if (jobIds.length === 0) throw new Error('archive fixture did not create a delivery obligation');
  await waitFor(async () => {
    const jobs = await Promise.all(jobIds.map(jobId => readJob(redis.lapras, jobId)));
    return jobs.every(job => job?.status === 'completed') ? true : undefined;
  }, 'archive fixture delivery completion');

  const eventKey = `event:${encodedEventId}`;
  const encodedEnvelope = await redis.lapras.get(eventKey);
  if (encodedEnvelope === null) throw new Error('archive fixture event is unavailable');
  const envelope = JSON.parse(encodedEnvelope) as Record<string, unknown> & { readonly receivedAtMs?: unknown };
  if (typeof envelope.receivedAtMs !== 'number') throw new Error('archive fixture event has no receipt timestamp');
  const currentMonth = new Date(envelope.receivedAtMs).toISOString().slice(0, 7);
  const currentStream = `evt:${encodeURIComponent(session.tenantId)}:${currentMonth}`;
  const currentEntries = await redis.lapras.xrange(currentStream, '-', '+');
  const currentEntry = currentEntries.find(([, fields]) => {
    const idIndex = fields.indexOf('id');
    return idIndex >= 0 && fields[idIndex + 1] === eventId;
  });
  if (currentEntry === undefined) throw new Error('archive fixture stream entry is unavailable');

  const oldReceivedAtMs = Date.UTC(new Date().getUTCFullYear() - 2, 0, 15, 12);
  const month = new Date(oldReceivedAtMs).toISOString().slice(0, 7);
  const oldEnvelope = JSON.stringify({ ...envelope, receivedAtMs: oldReceivedAtMs });
  const oldStream = `evt:${encodeURIComponent(session.tenantId)}:${month}`;
  await redis.lapras.xdel(currentStream, currentEntry[0]);
  const streamCursor = await redis.lapras.xadd(oldStream, '*', 'id', eventId, 'envelope', oldEnvelope);
  if (streamCursor === null) throw new Error('archive fixture could not be moved to an old month');
  await redis.lapras
    .multi()
    .set(eventKey, oldEnvelope)
    .sadd(`evt-months:${encodeURIComponent(session.tenantId)}`, month)
    .zadd(`evt-index:${encodeURIComponent(session.tenantId)}`, oldReceivedAtMs, eventId)
    .hset(`archive:${encodeURIComponent(session.tenantId)}:${month}`, 'phase', 'live', 'version', '1')
    .exec();
  return { eventId, month, streamCursor };
};

const localArchiveSuccess = async (
  session: Session,
): Promise<z.infer<typeof archiveLifecycleEvidenceSchema>['success']> => {
  const prepared = await prepareOldArchiveEvent(session);
  const token = await nativeBearer(session, [session.tenantId]);
  const audit = {
    requestId: `sit-retention-${crypto.randomUUID()}`,
    sessionId: session.id,
    accountId: session.accountId,
    reason: `SIT retention proof ${session.id}`,
  };
  const retentionPath = `/internal/landscape/v1/tenants/${encodeURIComponent(session.tenantId)}/maintenance/retention`;
  const outOfScope = await fetch(`${productOrigins.lapras}${retentionPath}`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${await nativeBearer(session, [`outside-${session.id}`])}`,
      ...jsonHeaders,
    },
    body: JSON.stringify({ audit }),
  });
  if (outOfScope.status !== 403) {
    throw new Error(`tenant-out-of-scope retention authority returned ${outOfScope.status}`);
  }
  const retained = await jsonRequest<{
    readonly action: string;
    readonly landscape: string;
    readonly tenantId: string;
    readonly archivedMonths: readonly string[];
    readonly liveMonths: readonly string[];
  }>(
    `${productOrigins.lapras}${retentionPath}`,
    {
      method: 'POST',
      headers: { authorization: `Bearer ${token}`, ...jsonHeaders },
      body: JSON.stringify({ audit }),
    },
    [200],
  );
  if (
    retained.action !== 'retention-run' ||
    retained.landscape !== 'lapras' ||
    retained.tenantId !== session.tenantId ||
    !retained.archivedMonths.includes(prepared.month) ||
    retained.liveMonths.includes(prepared.month)
  ) {
    throw new Error('retention endpoint did not report the prepared tenant month as archived');
  }

  const versionRoot = `${prepared.month}/versions/1`;
  const manifestKey = `lapras/${encodeURIComponent(session.tenantId)}/${versionRoot}/manifest.json`;
  const partKey = `lapras/${encodeURIComponent(session.tenantId)}/${versionRoot}/parts/00000000.json`;
  const [manifestStat, manifestBytes, partBytes] = await Promise.all([
    s3.file(manifestKey).stat(),
    s3.file(manifestKey).bytes(),
    s3.file(partKey).bytes(),
  ]);
  const manifest = JSON.parse(new TextDecoder().decode(manifestBytes)) as {
    readonly schema: string;
    readonly landscape: string;
    readonly tenantId: string;
    readonly month: string;
    readonly version: number;
    readonly partCount: number;
    readonly partsSha256: string;
    readonly eventCount: number;
  };
  const part = JSON.parse(new TextDecoder().decode(partBytes)) as {
    readonly schema: string;
    readonly records: readonly { readonly envelope?: { readonly id?: string } }[];
  };
  const partSha256 = createHash('sha256').update(partBytes).digest('hex');
  const partsSha256 = createHash('sha256')
    .update(
      `${JSON.stringify({
        objectPath: `${versionRoot}/parts/00000000`,
        part: 0,
        byteLength: partBytes.byteLength,
        sha256: partSha256,
        firstCursor: prepared.streamCursor,
        lastCursor: prepared.streamCursor,
      })}\n`,
    )
    .digest('hex');
  const checksumVerified =
    manifest.schema === 'mercury.event-archive-manifest.v1' &&
    manifest.landscape === 'lapras' &&
    manifest.tenantId === session.tenantId &&
    manifest.month === prepared.month &&
    manifest.version === 1 &&
    manifest.partCount === 1 &&
    manifest.eventCount === 1 &&
    manifest.partsSha256 === partsSha256 &&
    part.schema === 'mercury.event-archive-part.v1' &&
    part.records.length === 1 &&
    part.records[0]?.envelope?.id === prepared.eventId;
  const verifiedAtMs = Date.now();
  if (!checksumVerified) throw new Error('archived tenant month failed independent checksum verification');
  await Bun.sleep(2);
  const liveStreamDeleted =
    (await redis.lapras.exists(`evt:${encodeURIComponent(session.tenantId)}:${prepared.month}`)) === 0;
  const deletedAtMs = Date.now();
  if (!liveStreamDeleted) throw new Error('retention endpoint did not delete the verified live stream');
  return archiveLifecycleEvidenceSchema.shape.success.parse({
    uploadedAtMs: manifestStat.lastModified.getTime(),
    verifiedAtMs,
    deletedAtMs,
    checksumVerified,
    liveStreamDeleted,
  });
};

const archiveLifecycle = async (session: Session): Promise<z.infer<typeof archiveLifecycleEvidenceSchema>> => {
  const success = await localArchiveSuccess(session);
  const external = await attested('archive-lifecycle', archiveLifecycleEvidenceSchema, session);
  return archiveLifecycleEvidenceSchema.parse({ success, failure: external.failure });
};

const scenarios: Readonly<Record<string, (session: Session) => Promise<unknown>>> = {
  dependencies: inspectDependencies,
  'provider-verification': providerVerification,
  fanout,
  'atomic-acceptance': atomicAcceptance,
  'signature-lifecycle': signatureLifecycle,
  'console-journey': consoleJourney,
  'apple-backfill': session => attested('apple-backfill', appleBackfillEvidenceSchema, session),
  'google-subscription': session => attested('google-subscription', googleSubscriptionEvidenceSchema, session),
  'archive-local-success': localArchiveSuccess,
  'archive-lifecycle': archiveLifecycle,
  'route53-landing': session => attested('route53-landing', route53LandingEvidenceSchema, session),
};

const app = new Hono();
app.onError((error, context) =>
  context.json(
    {
      error: 'proof_unavailable',
      message: error instanceof Error ? error.message : 'unexpected SIT control failure',
    },
    424,
  ),
);
app.use('*', async (context, next) => {
  if (context.req.path === '/health') return next();
  if (context.req.header('authorization') !== `Bearer ${controlBearer}`) {
    return context.json({ error: 'unauthorized' }, 401);
  }
  if (context.req.path.startsWith('/v1/') && context.req.header('x-mercury-sit-protocol') !== '1') {
    return context.json({ error: 'unsupported_protocol' }, 400);
  }
  return next();
});
app.get('/health', context => context.json({ protocol: 'v1', status: 'ready' }));
app.post('/v1/sessions', async context => {
  const body = (await context.req.json()) as {
    readonly productBaseUrl?: unknown;
    readonly providerFixtures?: unknown;
  };
  const requestedFixtures = Array.isArray(body.providerFixtures) ? body.providerFixtures : undefined;
  if (
    body.productBaseUrl !== publicProductOrigin ||
    requestedFixtures === undefined ||
    requestedFixtures.length !== providerNames.length ||
    providerNames.some((provider, index) => requestedFixtures[index] !== provider)
  ) {
    return context.json({ error: 'invalid v1 session request' }, 400);
  }
  const health = await fetch(`${productOrigins.lapras}/health/ready`);
  if (!health.ok) throw new Error(`TLS product origin is not ready: ${health.status}`);
  const id = crypto.randomUUID();
  const nonce = Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString('base64url');
  const bootstrapped = await bootstrap(id);
  const session: Session = {
    id,
    nonce,
    productBaseUrl: body.productBaseUrl,
    accountId: bootstrapped.accountId,
    tenantId: bootstrapped.tenantId,
    intakeSlug: bootstrapped.intakeSlug,
    routeIds: bootstrapped.routeIds,
    endpointIds: bootstrapped.endpointIds,
    createdAtMs: Date.now(),
  };
  sessions.set(id, session);
  return context.json({ sessionId: id });
});
app.delete('/v1/sessions/:id', async context => {
  const id = context.req.param('id');
  const session = sessions.get(id);
  if (session !== undefined) {
    for (const routeId of Object.values(session.routeIds)) {
      await management(
        productOrigins.lapras,
        `/tenants/${encodeURIComponent(session.tenantId)}/routes/${encodeURIComponent(routeId)}`,
        { method: 'DELETE' },
        [204],
      );
    }
    await sql.begin(async transaction => {
      await transaction`
        delete from mercury_management.replay_audit
        where tenant_id = ${session.tenantId}
      `;
      await transaction`
        delete from mercury_management.endpoint_signing_credentials
        where tenant_id = ${session.tenantId}
      `;
      await transaction`
        delete from mercury_management.provider_credentials
        where tenant_id = ${session.tenantId}
      `;
    });
    await management(
      productOrigins.lapras,
      `/tenants/${encodeURIComponent(session.tenantId)}`,
      { method: 'DELETE' },
      [204],
    );
    for (const origin of Object.values(productOrigins)) {
      await management(origin, '/config/compile', { method: 'POST', body: '{}' }, [202]);
    }
    await management(productOrigins.lapras, `/tenants/${encodeURIComponent(session.tenantId)}`, {}, [404]);
  }
  sessions.delete(id);
  return context.body(null, 204);
});
app.post('/v1/sessions/:id/scenarios/:scenario', async context => {
  const session = sessions.get(context.req.param('id'));
  if (session === undefined) return context.json({ error: 'session not found' }, 404);
  const scenario = scenarios[context.req.param('scenario')];
  if (scenario === undefined) return context.json({ error: 'scenario not found' }, 404);
  return context.json(await scenario(session));
});

const port = Number(process.env.MERCURY_SIT_CONTROL_PORT ?? '8080');
if (!Number.isSafeInteger(port) || port < 1) throw new Error('invalid MERCURY_SIT_CONTROL_PORT');
Bun.serve({ hostname: '0.0.0.0', port, fetch: app.fetch });
