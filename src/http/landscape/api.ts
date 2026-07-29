import type { Result } from '@atomicloud/diene.result';
import { type Context, Hono } from 'hono';
import { z } from 'zod';
import type { DeliveryEngine } from '../../delivery/index.ts';
import type {
  ArchiveFailure,
  Clock,
  DeliveryJob,
  FlowStore,
  IdentifierFactory,
  RetainedEventQuery,
  RetainedEventRecord,
  RuntimeConfigReader,
  StorageFailure,
} from '../../domain/index.ts';
import type {
  LandscapeActionAuditDto,
  LandscapeActionReceiptDto,
  LandscapeDeadLetterDto,
  LandscapeDeadLetterListDto,
  LandscapeDeliveryJobDto,
  LandscapeEventDetailDto,
  LandscapeEventListDto,
  LandscapeEventSummaryDto,
  LandscapeHealthDto,
  LandscapeOperationsCapability,
  LandscapeProblemDto,
  LandscapeRetentionReceiptDto,
} from './dto.ts';

export interface LandscapeOperationsAuthorization {
  readonly subject: string;
  readonly accountId: string;
  readonly tenants: '*' | readonly string[];
  readonly capabilities: readonly LandscapeOperationsCapability[];
}

export interface LandscapeAuthenticationFailure {
  readonly code: 'invalid' | 'unavailable';
  readonly message: string;
}

export interface LandscapeOperationsAuthenticator {
  authenticate(request: Request): Promise<Result<LandscapeOperationsAuthorization, LandscapeAuthenticationFailure>>;
}

interface LandscapeSupervisorState {
  readonly running: boolean;
}

interface LandscapeRetentionRunner {
  run(
    tenantId: string,
  ): Promise<
    Result<
      Readonly<{ archivedMonths: readonly string[]; liveMonths: readonly string[] }>,
      ArchiveFailure | StorageFailure
    >
  >;
}

export interface LandscapeOperationsDependencies {
  readonly flow: FlowStore;
  readonly delivery: DeliveryEngine;
  readonly config: RuntimeConfigReader;
  readonly authenticator: LandscapeOperationsAuthenticator;
  readonly clock: Clock;
  readonly identifiers: IdentifierFactory;
  readonly retention: LandscapeRetentionRunner;
  readonly supervisor?: LandscapeSupervisorState;
}

type ProblemStatus = 400 | 401 | 403 | 404 | 409 | 500 | 503;

const problem = (context: Context, status: ProblemStatus, code: string, title: string, detail: string): Response =>
  context.json(
    {
      type: `https://atomi.cloud/problems/mercury/${code}`,
      title,
      status,
      code,
      detail,
    } satisfies LandscapeProblemDto,
    status,
  );

const identifierSchema = z
  .string()
  .min(1)
  .max(256)
  .regex(/^[A-Za-z0-9][A-Za-z0-9._~:/-]*$/);
const auditSchema = z
  .object({
    requestId: z.string().min(8).max(256),
    sessionId: z.string().min(8).max(256),
    accountId: z.string().min(1).max(256),
    reason: z.string().min(3).max(500),
  })
  .strict();
const eventQuerySchema = z
  .object({
    provider: z.string().min(1).max(128).optional(),
    routeId: identifierSchema.optional(),
    endpointId: identifierSchema.optional(),
    status: z.enum(['completed', 'dead-letter', 'paused', 'pending', 'retrying']).optional(),
    receivedAfterMs: z.coerce.number().int().nonnegative().optional(),
    receivedBeforeMs: z.coerce.number().int().nonnegative().optional(),
    cursor: z
      .string()
      .regex(/^(0|[1-9]\d*)$/)
      .optional(),
    limit: z.coerce.number().int().min(1).max(200).optional(),
  })
  .strict();
const replayEventSchema = z
  .object({
    endpointId: identifierSchema.optional(),
    audit: auditSchema,
  })
  .strict();
const endpointActionSchema = z.object({ audit: auditSchema }).strict();
const visibleEventHeaderNames = new Set(['content-type', 'traceparent', 'user-agent', 'x-request-id']);

interface AuthorizedRequest {
  readonly ok: true;
  readonly authorization: LandscapeOperationsAuthorization;
}

interface RejectedRequest {
  readonly ok: false;
  readonly response: Response;
}

const authorize = async (
  context: Context,
  dependencies: LandscapeOperationsDependencies,
  capability: LandscapeOperationsCapability,
  tenantId?: string,
): Promise<AuthorizedRequest | RejectedRequest> => {
  let authenticated: Awaited<ReturnType<LandscapeOperationsAuthenticator['authenticate']>>;
  try {
    authenticated = await dependencies.authenticator.authenticate(context.req.raw);
  } catch {
    return {
      ok: false,
      response: problem(context, 503, 'authentication-unavailable', 'Authentication unavailable', 'Try again later.'),
    };
  }
  if (await authenticated.isErr()) {
    const authFailure = await authenticated.unwrapErr();
    return {
      ok: false,
      response:
        authFailure.code === 'invalid'
          ? problem(
              context,
              401,
              'authentication-required',
              'Authentication required',
              'Valid authorization is required.',
            )
          : problem(context, 503, 'authentication-unavailable', 'Authentication unavailable', 'Try again later.'),
    };
  }

  const authorization = await authenticated.unwrap();
  const tenantAllowed =
    tenantId === undefined || authorization.tenants === '*' || authorization.tenants.includes(tenantId);
  if (!authorization.capabilities.includes(capability) || !tenantAllowed) {
    return {
      ok: false,
      response: problem(
        context,
        403,
        'forbidden',
        'Forbidden',
        'The requested operation is outside this authorization.',
      ),
    };
  }
  return { ok: true, authorization };
};

const eventSummary = (landscape: string, record: RetainedEventRecord): LandscapeEventSummaryDto => {
  const pendingDueTimes = record.jobs.filter(job => job.status === 'pending').map(job => job.dueAtMs);
  return {
    id: record.envelope.id,
    tenantId: record.envelope.tenantId,
    routeId: record.envelope.routeId,
    provider: record.envelope.provider,
    landscape,
    receivedAtMs: record.envelope.receivedAtMs,
    ...(record.envelope.providerEventId === undefined ? {} : { providerEventId: record.envelope.providerEventId }),
    ...(record.envelope.providerTimestampMs === undefined
      ? {}
      : { providerTimestampMs: record.envelope.providerTimestampMs }),
    ...(record.envelope.providerSequence === undefined ? {} : { providerSequence: record.envelope.providerSequence }),
    status: record.status,
    endpointIds: [...new Set(record.jobs.map(job => job.endpointId))],
    attemptCount: record.jobs.reduce((count, job) => count + job.attempts.length, 0),
    ...(pendingDueTimes.length === 0 ? {} : { nextDueAtMs: Math.min(...pendingDueTimes) }),
  };
};

const deliveryJob = (job: DeliveryJob): LandscapeDeliveryJobDto => ({
  id: job.id,
  eventId: job.eventId,
  endpointId: job.endpointId,
  address: job.address,
  addressKind: job.addressKind,
  createdAtMs: job.createdAtMs,
  dueAtMs: job.dueAtMs,
  retryWindowMs: job.retryWindowMs,
  status: job.status,
  attempts: job.attempts.map(attempt => ({
    number: attempt.number,
    attemptedAtMs: attempt.attemptedAtMs,
    address: attempt.address,
    ...(attempt.statusCode === undefined ? {} : { statusCode: attempt.statusCode }),
    ...(attempt.transportError === undefined ? {} : { transportError: attempt.transportError }),
    replay: attempt.replay,
  })),
  misrouteRefreshes: job.misrouteRefreshes,
  replayCount: job.replayCount,
});

const visibleEventHeaders = (headers: Readonly<Record<string, string>>): Readonly<Record<string, string>> =>
  Object.fromEntries(
    Object.entries(headers)
      .map(([name, value]) => [name.toLowerCase(), value] as const)
      .filter(([name]) => visibleEventHeaderNames.has(name)),
  );

const validIdentifier = (value: string): boolean => identifierSchema.safeParse(value).success;

const validAudit = (audit: LandscapeActionAuditDto, authorization: LandscapeOperationsAuthorization): boolean =>
  audit.accountId === authorization.accountId;

const storageProblem = (context: Context, code: 'action' | 'query', failureCode: string): Response => {
  if (failureCode === 'invalid-data') {
    return problem(
      context,
      code === 'query' ? 400 : 404,
      code === 'query' ? 'invalid-query' : 'not-found',
      code === 'query' ? 'Invalid query' : 'Resource not found',
      code === 'query' ? 'The retained-event query is invalid.' : 'The requested retained resource was not found.',
    );
  }
  if (failureCode === 'conflict') {
    return problem(context, 409, 'conflict', 'Conflict', 'The retained resource changed concurrently.');
  }
  return problem(context, 503, 'storage-unavailable', 'Storage unavailable', 'Try again later.');
};

export const createLandscapeOperationsApi = (dependencies: LandscapeOperationsDependencies): Hono => {
  const app = new Hono();

  app.get('/health', async context => {
    const authorized = await authorize(context, dependencies, 'operations:read');
    if (!authorized.ok) {
      return authorized.response;
    }
    const active = await dependencies.config.readActive();
    if (await active.isErr()) {
      return problem(context, 503, 'config-unavailable', 'Runtime configuration unavailable', 'Try again later.');
    }
    const config = await active.unwrap();
    const supervisor =
      dependencies.supervisor === undefined ? 'unknown' : dependencies.supervisor.running ? 'running' : 'stopped';
    const response: LandscapeHealthDto = {
      landscape: dependencies.flow.landscape,
      status:
        config !== null &&
        config.landscape === dependencies.flow.landscape &&
        (supervisor === 'running' || supervisor === 'unknown')
          ? 'healthy'
          : 'degraded',
      checkedAtMs: dependencies.clock.nowMs(),
      activeGeneration: config?.generation ?? null,
      ...(config === null
        ? {}
        : {
            compiledAtMs: config.compiledAtMs,
            sourceRevision: config.sourceRevision,
          }),
      supervisor,
    };
    return context.json(response);
  });

  app.get('/tenants/:tenantId/events', async context => {
    const tenantId = context.req.param('tenantId');
    if (!validIdentifier(tenantId)) {
      return problem(context, 400, 'invalid-tenant', 'Invalid tenant', 'The tenant reference is invalid.');
    }
    const authorized = await authorize(context, dependencies, 'operations:read', tenantId);
    if (!authorized.ok) {
      return authorized.response;
    }
    const parsed = eventQuerySchema.safeParse(context.req.query());
    if (!parsed.success || (parsed.data.receivedAfterMs ?? 0) > (parsed.data.receivedBeforeMs ?? Number.MAX_VALUE)) {
      return problem(context, 400, 'invalid-query', 'Invalid query', 'The retained-event filters are invalid.');
    }
    const query: RetainedEventQuery = { tenantId, ...parsed.data };
    const page = await dependencies.flow.listRetainedEvents(query);
    if (await page.isErr()) {
      return storageProblem(context, 'query', (await page.unwrapErr()).code);
    }
    const retained = await page.unwrap();
    const response: LandscapeEventListDto = {
      landscape: dependencies.flow.landscape,
      tenantId,
      items: retained.items.map(item => eventSummary(dependencies.flow.landscape, item)),
      ...(retained.nextCursor === undefined ? {} : { nextCursor: retained.nextCursor }),
    };
    return context.json(response);
  });

  app.get('/tenants/:tenantId/events/:eventId', async context => {
    const tenantId = context.req.param('tenantId');
    const eventId = context.req.param('eventId');
    if (!validIdentifier(tenantId) || !validIdentifier(eventId)) {
      return problem(
        context,
        400,
        'invalid-reference',
        'Invalid reference',
        'The tenant or event reference is invalid.',
      );
    }
    const authorized = await authorize(context, dependencies, 'operations:read', tenantId);
    if (!authorized.ok) {
      return authorized.response;
    }
    const [storedEvent, storedJobs] = await Promise.all([
      dependencies.flow.getEvent(eventId),
      dependencies.flow.listEventJobs(eventId),
    ]);
    if (await storedEvent.isErr()) {
      return storageProblem(context, 'action', (await storedEvent.unwrapErr()).code);
    }
    if (await storedJobs.isErr()) {
      return storageProblem(context, 'action', (await storedJobs.unwrapErr()).code);
    }
    const envelope = await storedEvent.unwrap();
    if (envelope === null || envelope.tenantId !== tenantId) {
      return problem(context, 404, 'not-found', 'Event not found', 'The retained event was not found.');
    }
    const jobs = await storedJobs.unwrap();
    const status = jobs.some(job => job.status === 'dead-letter')
      ? 'dead-letter'
      : jobs.some(job => job.status === 'paused')
        ? 'paused'
        : jobs.length === 0 || jobs.every(job => job.status === 'completed')
          ? 'completed'
          : jobs.some(job => job.attempts.length > 0)
            ? 'retrying'
            : 'pending';
    const response: LandscapeEventDetailDto = {
      event: eventSummary(dependencies.flow.landscape, {
        envelope,
        jobs,
        status,
      }),
      headers: visibleEventHeaders(envelope.headers),
      verificationMetadata: envelope.verificationMetadata,
      rawBodyBase64: Buffer.from(envelope.rawBody).toString('base64'),
      jobs: jobs.map(deliveryJob),
    };
    return context.json(response);
  });

  app.get('/tenants/:tenantId/dlq', async context => {
    const tenantId = context.req.param('tenantId');
    if (!validIdentifier(tenantId)) {
      return problem(context, 400, 'invalid-tenant', 'Invalid tenant', 'The tenant reference is invalid.');
    }
    const authorized = await authorize(context, dependencies, 'operations:read', tenantId);
    if (!authorized.ok) {
      return authorized.response;
    }
    const entries = await dependencies.flow.listDeadLetters(tenantId);
    if (await entries.isErr()) {
      return storageProblem(context, 'query', (await entries.unwrapErr()).code);
    }
    const items: LandscapeDeadLetterDto[] = [];
    for (const entry of await entries.unwrap()) {
      const [storedEvent, storedJob] = await Promise.all([
        dependencies.flow.getEvent(entry.eventId),
        dependencies.flow.getJob(entry.jobId),
      ]);
      if (await storedEvent.isErr()) {
        return storageProblem(context, 'query', (await storedEvent.unwrapErr()).code);
      }
      if (await storedJob.isErr()) {
        return storageProblem(context, 'query', (await storedJob.unwrapErr()).code);
      }
      const envelope = await storedEvent.unwrap();
      const job = await storedJob.unwrap();
      const finalAttempt = job?.attempts.at(-1);
      items.push({
        landscape: entry.landscape,
        tenantId: entry.tenantId,
        eventId: entry.eventId,
        endpointId: entry.endpointId,
        jobId: entry.jobId,
        ...(envelope === null ? {} : { provider: envelope.provider }),
        exhaustedAtMs: entry.exhaustedAtMs,
        reason: entry.reason,
        attemptCount: job?.attempts.length ?? 0,
        ...(finalAttempt?.statusCode !== undefined
          ? { finalOutcome: finalAttempt.statusCode }
          : finalAttempt?.transportError === undefined
            ? {}
            : { finalOutcome: finalAttempt.transportError }),
      });
    }
    return context.json({
      landscape: dependencies.flow.landscape,
      tenantId,
      items,
    } satisfies LandscapeDeadLetterListDto);
  });

  app.post('/tenants/:tenantId/maintenance/retention', async context => {
    const tenantId = context.req.param('tenantId');
    if (!validIdentifier(tenantId)) {
      return problem(context, 400, 'invalid-tenant', 'Invalid tenant', 'The tenant reference is invalid.');
    }
    const authorized = await authorize(context, dependencies, 'retention:run', tenantId);
    if (!authorized.ok) {
      return authorized.response;
    }
    let json: unknown;
    try {
      json = await context.req.json();
    } catch {
      return problem(context, 400, 'invalid-body', 'Invalid request body', 'A JSON retention request is required.');
    }
    const parsed = endpointActionSchema.safeParse(json);
    if (!parsed.success || !validAudit(parsed.data.audit, authorized.authorization)) {
      return problem(
        context,
        400,
        'invalid-body',
        'Invalid request body',
        'The retention request or audit context is invalid.',
      );
    }
    let retained: Awaited<ReturnType<LandscapeRetentionRunner['run']>>;
    try {
      retained = await dependencies.retention.run(tenantId);
    } catch {
      return problem(context, 503, 'retention-unavailable', 'Retention unavailable', 'Try again later.');
    }
    if (await retained.isErr()) {
      return problem(context, 503, 'retention-unavailable', 'Retention unavailable', 'Try again later.');
    }
    const result = await retained.unwrap();
    const response: LandscapeRetentionReceiptDto = {
      actionId: dependencies.identifiers.create(),
      action: 'retention-run',
      landscape: dependencies.flow.landscape,
      tenantId,
      completedAtMs: dependencies.clock.nowMs(),
      archivedMonths: result.archivedMonths,
      liveMonths: result.liveMonths,
    };
    return context.json(response);
  });

  app.post('/tenants/:tenantId/events/:eventId/replay', async context => {
    const tenantId = context.req.param('tenantId');
    const eventId = context.req.param('eventId');
    if (!validIdentifier(tenantId) || !validIdentifier(eventId)) {
      return problem(
        context,
        400,
        'invalid-reference',
        'Invalid reference',
        'The tenant or event reference is invalid.',
      );
    }
    const authorized = await authorize(context, dependencies, 'events:replay', tenantId);
    if (!authorized.ok) {
      return authorized.response;
    }
    let json: unknown;
    try {
      json = await context.req.json();
    } catch {
      return problem(context, 400, 'invalid-body', 'Invalid request body', 'A JSON replay request is required.');
    }
    const parsed = replayEventSchema.safeParse(json);
    if (!parsed.success || !validAudit(parsed.data.audit, authorized.authorization)) {
      return problem(
        context,
        400,
        'invalid-body',
        'Invalid request body',
        'The replay request or audit context is invalid.',
      );
    }
    const storedEvent = await dependencies.flow.getEvent(eventId);
    if (await storedEvent.isErr()) {
      return storageProblem(context, 'action', (await storedEvent.unwrapErr()).code);
    }
    const envelope = await storedEvent.unwrap();
    if (envelope === null || envelope.tenantId !== tenantId) {
      return problem(context, 404, 'not-found', 'Event not found', 'The retained event was not found.');
    }
    const replayed =
      parsed.data.endpointId === undefined
        ? await dependencies.delivery.replayEvent(eventId)
        : await dependencies.delivery.replayEndpoint(eventId, parsed.data.endpointId);
    if (await replayed.isErr()) {
      return problem(context, 503, 'replay-unavailable', 'Replay unavailable', 'Try again later.');
    }
    const value = await replayed.unwrap();
    const response: LandscapeActionReceiptDto = {
      actionId: dependencies.identifiers.create(),
      action: 'event-replayed',
      landscape: dependencies.flow.landscape,
      tenantId,
      acceptedAtMs: dependencies.clock.nowMs(),
      affectedCount: Array.isArray(value) ? value.length : 1,
    };
    return context.json(response, 202);
  });

  app.post('/tenants/:tenantId/endpoints/:endpointId/replay', async context => {
    const tenantId = context.req.param('tenantId');
    const endpointId = context.req.param('endpointId');
    if (!validIdentifier(tenantId) || !validIdentifier(endpointId)) {
      return problem(
        context,
        400,
        'invalid-reference',
        'Invalid reference',
        'The tenant or endpoint reference is invalid.',
      );
    }
    const authorized = await authorize(context, dependencies, 'endpoints:replay', tenantId);
    if (!authorized.ok) {
      return authorized.response;
    }
    let json: unknown;
    try {
      json = await context.req.json();
    } catch {
      return problem(context, 400, 'invalid-body', 'Invalid request body', 'A JSON replay request is required.');
    }
    const parsed = endpointActionSchema.safeParse(json);
    if (!parsed.success || !validAudit(parsed.data.audit, authorized.authorization)) {
      return problem(
        context,
        400,
        'invalid-body',
        'Invalid request body',
        'The replay request or audit context is invalid.',
      );
    }
    const replayed = await dependencies.delivery.replayEndpointFailures(tenantId, endpointId);
    if (await replayed.isErr()) {
      return problem(context, 503, 'replay-unavailable', 'Replay unavailable', 'Try again later.');
    }
    const jobs = await replayed.unwrap();
    return context.json(
      {
        actionId: dependencies.identifiers.create(),
        action: 'endpoint-replayed',
        landscape: dependencies.flow.landscape,
        tenantId,
        acceptedAtMs: dependencies.clock.nowMs(),
        affectedCount: jobs.length,
      } satisfies LandscapeActionReceiptDto,
      202,
    );
  });

  app.post('/tenants/:tenantId/endpoints/:endpointId/circuit/re-enable', async context => {
    const tenantId = context.req.param('tenantId');
    const endpointId = context.req.param('endpointId');
    if (!validIdentifier(tenantId) || !validIdentifier(endpointId)) {
      return problem(
        context,
        400,
        'invalid-reference',
        'Invalid reference',
        'The tenant or endpoint reference is invalid.',
      );
    }
    const authorized = await authorize(context, dependencies, 'endpoints:reenable', tenantId);
    if (!authorized.ok) {
      return authorized.response;
    }
    let json: unknown;
    try {
      json = await context.req.json();
    } catch {
      return problem(context, 400, 'invalid-body', 'Invalid request body', 'A JSON circuit request is required.');
    }
    const parsed = endpointActionSchema.safeParse(json);
    if (!parsed.success || !validAudit(parsed.data.audit, authorized.authorization)) {
      return problem(
        context,
        400,
        'invalid-body',
        'Invalid request body',
        'The circuit request or audit context is invalid.',
      );
    }
    const closed = await dependencies.delivery.manualClose(tenantId, endpointId);
    if (await closed.isErr()) {
      return problem(context, 503, 'circuit-unavailable', 'Circuit action unavailable', 'Try again later.');
    }
    return context.json(
      {
        actionId: dependencies.identifiers.create(),
        action: 'circuit-reenabled',
        landscape: dependencies.flow.landscape,
        tenantId,
        acceptedAtMs: dependencies.clock.nowMs(),
        affectedCount: 1,
      } satisfies LandscapeActionReceiptDto,
      202,
    );
  });

  app.notFound(context => problem(context, 404, 'not-found', 'Not found', 'The operations route was not found.'));

  app.onError((_error, context) =>
    problem(context, 500, 'unexpected', 'Unexpected failure', 'The operation could not be completed.'),
  );

  return app;
};
