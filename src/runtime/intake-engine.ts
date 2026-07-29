import { Err, Ok, type Result } from '@atomicloud/diene.result';
import {
  boundedRetryWindowMs,
  type Clock,
  DEDUP_WINDOW_SECONDS,
  type DeliveryJob,
  dedupKey,
  deriveDedupId,
  type EndpointObligation,
  type FlowStore,
  type HeaderMap,
  type IdentifierFactory,
  type IntakeFailure,
  type IntakeOutcome,
  type IntakeRequest,
  type NameBlindRouteResolver,
  type ProviderVerifierRegistry,
  type RuntimeConfigReader,
  type RuntimeTelemetry,
  type WebhookEnvelope,
} from '../domain/index.ts';
import {
  boundedJsonDocumentByteLength,
  MAX_ATOMIC_ACCEPT_COMMAND_BYTES,
  runtimeConfigBoundsFailure,
} from './config.ts';

const defaultPersistedHeaders = new Set(['content-type', 'user-agent', 'x-request-id']);
const ATOMIC_ACCEPT_PROTOCOL_HEADROOM_BYTES = 64 * 1_024;

const filterHeaders = (headers: HeaderMap, allowed: ReadonlySet<string>): HeaderMap =>
  Object.fromEntries(Object.entries(headers).filter(([name]) => allowed.has(name.toLowerCase())));

const atomicAcceptCommandFits = (
  deduplicationKey: string,
  envelope: WebhookEnvelope,
  jobs: readonly DeliveryJob[],
): boolean => {
  const persistedEnvelopeShape = {
    ...envelope,
    rawBody: undefined,
    rawBodyBase64: '',
  };
  // The storage command also carries a fixed Lua program, RESP framing, and
  // constant key prefixes. Reserve explicit headroom for those bytes, then
  // conservatively account for every attacker-influenced key and argument.
  let bytes = ATOMIC_ACCEPT_PROTOCOL_HEADROOM_BYTES;
  bytes += boundedJsonDocumentByteLength(persistedEnvelopeShape, MAX_ATOMIC_ACCEPT_COMMAND_BYTES);
  bytes += 4 * Math.ceil(envelope.rawBody.byteLength / 3);
  bytes += Buffer.byteLength(deduplicationKey);
  bytes += Buffer.byteLength(envelope.id) * 7;
  bytes += Buffer.byteLength(envelope.tenantId) * 15;
  if (bytes > MAX_ATOMIC_ACCEPT_COMMAND_BYTES) return false;

  for (const job of jobs) {
    bytes += boundedJsonDocumentByteLength(job, MAX_ATOMIC_ACCEPT_COMMAND_BYTES);
    // One percent-encoded Redis key (at most three output bytes per input
    // byte) plus the unencoded job-id argument.
    bytes += Buffer.byteLength(job.id) * 4;
    if (bytes > MAX_ATOMIC_ACCEPT_COMMAND_BYTES) return false;
  }
  return true;
};

const intakeFailure = (
  code: IntakeFailure['code'],
  message: string,
  retryAfterSeconds?: number,
  context: Pick<IntakeFailure, 'landscape' | 'provider' | 'tenantId'> = {},
): IntakeFailure => ({
  code,
  message,
  ...(retryAfterSeconds === undefined ? {} : { retryAfterSeconds }),
  ...context,
});

export class IntakeEngine {
  constructor(
    readonly configStore: RuntimeConfigReader,
    readonly flowStore: FlowStore,
    readonly verifier: ProviderVerifierRegistry,
    readonly resolver: NameBlindRouteResolver,
    readonly clock: Clock,
    readonly identifiers: IdentifierFactory,
    readonly telemetry: RuntimeTelemetry,
    readonly persistedHeaders: ReadonlySet<string> = defaultPersistedHeaders,
  ) {}

  async intake(request: IntakeRequest): Promise<Result<IntakeOutcome, IntakeFailure>> {
    let configResult: Awaited<ReturnType<RuntimeConfigReader['readActive']>>;
    try {
      configResult = await this.configStore.readActive();
    } catch {
      await this.telemetry.record({
        name: 'intake.unavailable',
        attributes: {
          landscape: this.flowStore.landscape,
          operation: 'config',
        },
      });
      return Err(
        intakeFailure('config-unavailable', 'runtime configuration is temporarily unavailable', undefined, {
          landscape: this.flowStore.landscape,
        }),
      );
    }
    if (await configResult.isErr()) {
      await this.telemetry.record({
        name: 'intake.unavailable',
        attributes: {
          landscape: this.flowStore.landscape,
          operation: 'config',
        },
      });
      return Err(
        intakeFailure('config-unavailable', 'runtime configuration is temporarily unavailable', undefined, {
          landscape: this.flowStore.landscape,
        }),
      );
    }
    const config = await configResult.unwrap();
    if (config === null) {
      await this.telemetry.record({
        name: 'intake.unavailable',
        attributes: {
          landscape: this.flowStore.landscape,
          operation: 'config',
        },
      });
      return Err(
        intakeFailure('config-unavailable', 'no active runtime configuration', undefined, {
          landscape: this.flowStore.landscape,
        }),
      );
    }

    const boundsFailure = runtimeConfigBoundsFailure(config);
    if (boundsFailure !== null) {
      await this.telemetry.record({
        name: 'intake.unavailable',
        attributes: {
          landscape: config.landscape,
          operation: 'config-bounds',
        },
      });
      return Err(
        intakeFailure('config-unavailable', 'active runtime configuration exceeds safe bounds', undefined, {
          landscape: config.landscape,
        }),
      );
    }

    const resolved = this.resolver.resolve(config, request.path, request.host);
    if (
      resolved === null ||
      (resolved.route.orphanedUntilMs !== undefined && resolved.route.orphanedUntilMs <= this.clock.nowMs())
    ) {
      await this.telemetry.record({
        name: 'route.unknown',
        attributes: { landscape: config.landscape },
      });
      return Err(
        intakeFailure('unknown-route', 'webhook route is not registered', undefined, { landscape: config.landscape }),
      );
    }

    await this.telemetry.record({
      name: 'intake.received',
      attributes: {
        landscape: config.landscape,
        provider: resolved.route.provider,
        tenant: resolved.tenant.id,
      },
    });

    const receivedAtMs = this.clock.nowMs();
    let verification: Awaited<ReturnType<ProviderVerifierRegistry['verify']>>;
    try {
      verification = await this.verifier.verify({
        provider: resolved.route.provider,
        registeredUrl: resolved.route.registeredUrl,
        ...(resolved.route.verificationSecretRefs === undefined
          ? {}
          : { verificationSecretRefs: resolved.route.verificationSecretRefs }),
        ...(resolved.route.verificationSecretRef === undefined
          ? {}
          : { verificationSecretRef: resolved.route.verificationSecretRef }),
        headers: request.headers,
        rawBody: request.rawBody,
      });
    } catch {
      await this.telemetry.record({
        name: 'intake.unavailable',
        attributes: {
          landscape: config.landscape,
          operation: 'verifier',
          provider: resolved.route.provider,
        },
      });
      return Err(
        intakeFailure('config-unavailable', 'provider verification is temporarily unavailable', undefined, {
          landscape: config.landscape,
          provider: resolved.route.provider,
          tenantId: resolved.tenant.id,
        }),
      );
    }
    if (await verification.isErr()) {
      const failure = await verification.unwrapErr();
      if (failure.code === 'invalid-signature') {
        await this.telemetry.record({
          name: 'verification.failure',
          attributes: {
            landscape: config.landscape,
            provider: resolved.route.provider,
            tenant: resolved.tenant.id,
          },
        });
        return Err(
          intakeFailure('verification-failed', 'provider request authentication failed', undefined, {
            landscape: config.landscape,
            provider: resolved.route.provider,
            tenantId: resolved.tenant.id,
          }),
        );
      }
      await this.telemetry.record({
        name: 'intake.unavailable',
        attributes: {
          landscape: config.landscape,
          operation: 'verifier',
          provider: resolved.route.provider,
        },
      });
      return Err(
        intakeFailure('config-unavailable', 'provider verification is temporarily unavailable', undefined, {
          landscape: config.landscape,
          provider: resolved.route.provider,
          tenantId: resolved.tenant.id,
        }),
      );
    }

    const evidence = await verification.unwrap();
    const quotaResult = await this.flowStore.consumeQuota({
      tenantId: resolved.tenant.id,
      ratePerSecond: resolved.tenant.intakeRps,
      burst: resolved.tenant.intakeBurst,
      nowMs: this.clock.nowMs(),
    });
    if (await quotaResult.isErr()) {
      await this.telemetry.record({
        name: 'intake.unavailable',
        attributes: {
          landscape: config.landscape,
          operation: 'persistence',
          provider: resolved.route.provider,
        },
      });
      return Err(
        intakeFailure('persistence-unavailable', (await quotaResult.unwrapErr()).message, undefined, {
          landscape: config.landscape,
          provider: resolved.route.provider,
          tenantId: resolved.tenant.id,
        }),
      );
    }
    const quota = await quotaResult.unwrap();
    if (!quota.allowed) {
      await this.telemetry.record({
        name: 'quota.exhausted',
        attributes: {
          landscape: config.landscape,
          provider: resolved.route.provider,
          tenant: resolved.tenant.id,
        },
      });
      return Err(
        intakeFailure('quota-exhausted', 'tenant intake quota exhausted', quota.retryAfterSeconds, {
          landscape: config.landscape,
          provider: resolved.route.provider,
          tenantId: resolved.tenant.id,
        }),
      );
    }

    const derivedDedupId = deriveDedupId(evidence.providerEventId, request.rawBody, evidence.signatureMaterial);
    const eventId = this.identifiers.create();
    const obligations: readonly EndpointObligation[] = resolved.route.endpoints.map(endpoint => ({
      id: `${eventId}:${encodeURIComponent(endpoint.id)}`,
      endpointId: endpoint.id,
      address: endpoint.address,
      addressKind: endpoint.addressKind,
      signingSecretRef: endpoint.signingSecretRef,
    }));
    const envelope: WebhookEnvelope = {
      id: eventId,
      tenantId: resolved.tenant.id,
      routeId: resolved.route.id,
      provider: resolved.route.provider,
      landingLandscape: config.landscape,
      receivedAtMs,
      ...(evidence.providerTimestampMs === undefined ? {} : { providerTimestampMs: evidence.providerTimestampMs }),
      ...(evidence.providerSequence === undefined ? {} : { providerSequence: evidence.providerSequence }),
      ...(evidence.providerEventId === undefined ? {} : { providerEventId: evidence.providerEventId }),
      dedupId: derivedDedupId,
      rawBody: request.rawBody.slice(),
      headers: filterHeaders(request.headers, this.persistedHeaders),
      verificationMetadata: evidence.metadata,
      obligations,
    };
    const jobs: readonly DeliveryJob[] = obligations.map(obligation => ({
      id: obligation.id,
      eventId,
      tenantId: resolved.tenant.id,
      routeId: resolved.route.id,
      endpointId: obligation.endpointId,
      address: obligation.address,
      addressKind: obligation.addressKind,
      signingSecretRef: obligation.signingSecretRef,
      createdAtMs: receivedAtMs,
      dueAtMs: receivedAtMs,
      retryWindowMs: boundedRetryWindowMs(resolved.tenant.retryWindowMs),
      status: 'pending',
      attempts: [],
      misrouteRefreshes: 0,
      replayCount: 0,
    }));

    const scopedDedupKey = dedupKey(resolved.tenant.id, resolved.route.id, derivedDedupId);
    if (!atomicAcceptCommandFits(scopedDedupKey, envelope, jobs)) {
      await this.telemetry.record({
        name: 'intake.unavailable',
        attributes: {
          landscape: config.landscape,
          operation: 'fanout-bounds',
          provider: resolved.route.provider,
        },
      });
      return Err(
        intakeFailure('config-unavailable', 'runtime fan-out exceeds safe persistence bounds', undefined, {
          landscape: config.landscape,
          provider: resolved.route.provider,
          tenantId: resolved.tenant.id,
        }),
      );
    }

    const accepted = await this.flowStore.acceptOnce({
      dedupKey: scopedDedupKey,
      dedupTtlSeconds: DEDUP_WINDOW_SECONDS,
      envelope,
      jobs,
    });
    if (await accepted.isErr()) {
      await this.telemetry.record({
        name: 'intake.unavailable',
        attributes: {
          landscape: config.landscape,
          operation: 'persistence',
          provider: resolved.route.provider,
        },
      });
      return Err(
        intakeFailure('persistence-unavailable', (await accepted.unwrapErr()).message, undefined, {
          landscape: config.landscape,
          provider: resolved.route.provider,
          tenantId: resolved.tenant.id,
        }),
      );
    }
    const acceptance = await accepted.unwrap();
    if (acceptance.kind === 'duplicate') {
      await this.telemetry.record({
        name: 'dedup.hit',
        attributes: {
          landscape: config.landscape,
          provider: resolved.route.provider,
          tenant: resolved.tenant.id,
        },
      });
      return Ok({
        kind: 'duplicate',
        dedupId: derivedDedupId,
        eventId: acceptance.eventId,
      });
    }

    await this.telemetry.record({
      name: 'intake.accepted',
      attributes: {
        landscape: config.landscape,
        obligations: obligations.length,
        provider: resolved.route.provider,
        tenant: resolved.tenant.id,
      },
    });
    return Ok({ kind: 'accepted', eventId: acceptance.eventId });
  }

  async acknowledgeProviderResponse(eventId: string): Promise<Result<void, IntakeFailure>> {
    const acknowledged = await this.flowStore.acknowledgeEvent(eventId, this.clock.nowMs());
    if (await acknowledged.isErr()) {
      await this.telemetry.record({
        name: 'intake.unavailable',
        attributes: {
          landscape: this.flowStore.landscape,
          operation: 'persistence',
        },
      });
      return Err(
        intakeFailure('persistence-unavailable', (await acknowledged.unwrapErr()).message, undefined, {
          landscape: this.flowStore.landscape,
        }),
      );
    }
    return Ok(undefined);
  }
}
