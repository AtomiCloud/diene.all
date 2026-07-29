import { Err, Ok, type Result } from '@atomicloud/diene.result';
import {
  type Clock,
  DEFAULT_CIRCUIT_FAILURE_WINDOW_MS,
  DELIVERY_ENVELOPE_MEDIA_TYPE,
  type DeliveryFailure,
  type DeliveryJob,
  type DeliveryJobClaim,
  type DeliveryTransport,
  type EndpointRefresher,
  type FlowStore,
  type InternalDeliverySigner,
  nextRetry,
  type RuntimeTelemetry,
  type SecretReader,
  serializeCanonicalDeliveryEnvelope,
} from '../domain/index.ts';
import { withDeliveryAddressKind } from './transport.ts';

export type DeliveryProcessOutcome =
  | Readonly<{ kind: 'completed'; jobId: string }>
  | Readonly<{ dueAtMs: number; kind: 'retry'; jobId: string }>
  | Readonly<{ kind: 'dead-letter'; jobId: string }>
  | Readonly<{ kind: 'paused'; jobId: string }>
  | Readonly<{ kind: 'skipped'; jobId: string }>;

export interface ProcessOptions {
  readonly bypassCircuit?: boolean;
  readonly signal?: AbortSignal;
}

export const deliveryEndpointKey = (tenantId: string, endpointId: string): string =>
  `${encodeURIComponent(tenantId)}:${encodeURIComponent(endpointId)}`;

const storageFailure = (message: string): DeliveryFailure => ({
  code: 'storage-unavailable',
  message,
});
const aborted = (signal: AbortSignal | undefined): boolean => signal?.aborted === true;

const outboundHeaders = (signature: string): Readonly<Record<string, string>> => ({
  'content-type': DELIVERY_ENVELOPE_MEDIA_TYPE,
  'x-atomi-webhook-signature': signature,
});

export class DeliveryEngine {
  constructor(
    readonly flow: FlowStore,
    readonly transport: DeliveryTransport,
    readonly secrets: SecretReader,
    readonly refresher: EndpointRefresher,
    readonly clock: Clock,
    readonly signer: InternalDeliverySigner,
    readonly telemetry: RuntimeTelemetry,
    readonly circuitFailureWindowMs = DEFAULT_CIRCUIT_FAILURE_WINDOW_MS,
    readonly claimLeaseMs = 30_000,
    readonly claimTokenFactory: () => string = () => crypto.randomUUID(),
  ) {
    if (!Number.isSafeInteger(claimLeaseMs) || claimLeaseMs < 1) {
      throw new RangeError('delivery claim lease must be a positive integer millisecond duration');
    }
  }

  async process(jobId: string, options: ProcessOptions = {}): Promise<Result<DeliveryProcessOutcome, DeliveryFailure>> {
    if (aborted(options.signal)) {
      return Ok({ kind: 'skipped', jobId });
    }
    const claimed = await this.flow.claimJob(jobId, {
      claimToken: this.claimTokenFactory(),
      leaseMs: this.claimLeaseMs,
      nowMs: this.clock.nowMs(),
    });
    if (await claimed.isErr()) {
      return Err(storageFailure((await claimed.unwrapErr()).message));
    }
    const claim = await claimed.unwrap();
    if (claim === null) {
      return Ok({ kind: 'skipped', jobId });
    }
    return this.processClaimed(claim, options);
  }

  private async processClaimed(
    claim: DeliveryJobClaim,
    options: ProcessOptions,
  ): Promise<Result<DeliveryProcessOutcome, DeliveryFailure>> {
    const jobId = claim.job.id;
    if (aborted(options.signal)) {
      await this.releaseClaim(jobId, claim.claimToken);
      return Ok({ kind: 'skipped', jobId });
    }
    const jobResult = await this.flow.getJob(jobId);
    if (await jobResult.isErr()) {
      await this.releaseClaim(jobId, claim.claimToken);
      return Err(storageFailure((await jobResult.unwrapErr()).message));
    }
    const job = await jobResult.unwrap();
    if (job === null) {
      await this.releaseClaim(jobId, claim.claimToken);
      return Err(storageFailure('delivery job not found'));
    }
    if (job.status === 'completed' || job.status === 'dead-letter') {
      await this.releaseClaim(jobId, claim.claimToken);
      return Ok({ kind: 'skipped', jobId });
    }

    const nowMs = this.clock.nowMs();
    if (nowMs >= job.createdAtMs + job.retryWindowMs) {
      return this.moveToDeadLetter(job, nowMs, 'retry window exhausted', claim.claimToken);
    }

    const endpointKey = deliveryEndpointKey(job.tenantId, job.endpointId);
    const circuitResult = await this.flow.getCircuit(endpointKey);
    if (await circuitResult.isErr()) {
      await this.releaseClaim(jobId, claim.claimToken);
      return Err(storageFailure((await circuitResult.unwrapErr()).message));
    }
    const circuit = await circuitResult.unwrap();
    if (circuit.status === 'open' && options.bypassCircuit !== true) {
      const paused = await this.flow.pauseJob(jobId, claim.claimToken);
      if (await paused.isErr()) {
        return Err(storageFailure((await paused.unwrapErr()).message));
      }
      return Ok({ kind: 'paused', jobId });
    }

    const eventResult = await this.flow.getEvent(job.eventId);
    if (await eventResult.isErr()) {
      await this.releaseClaim(jobId, claim.claimToken);
      return Err(storageFailure((await eventResult.unwrapErr()).message));
    }
    const event = await eventResult.unwrap();
    if (event === null) {
      await this.releaseClaim(jobId, claim.claimToken);
      return Err(storageFailure('delivery event not found'));
    }
    if (event.acknowledgedAtMs === undefined) {
      await this.releaseClaim(jobId, claim.claimToken);
      return Ok({ kind: 'skipped', jobId });
    }

    const secretResult = await this.secrets.read(job.signingSecretRef);
    if (await secretResult.isErr()) {
      await this.releaseClaim(jobId, claim.claimToken);
      return Err({
        code: 'secret-unavailable',
        message: (await secretResult.unwrapErr()).message,
      });
    }
    const secret = await secretResult.unwrap();
    if (aborted(options.signal)) {
      await this.releaseClaim(jobId, claim.claimToken);
      return Ok({ kind: 'skipped', jobId });
    }
    const priorTimestamp = job.attempts.at(-1)?.signatureTimestampSeconds ?? -1;
    const signatureTimestampSeconds = Math.max(Math.floor(nowMs / 1_000), priorTimestamp + 1);
    const attemptNumber = job.attempts.length + 1;
    let deliveryBody: Uint8Array;
    try {
      deliveryBody = serializeCanonicalDeliveryEnvelope({
        attempt: attemptNumber,
        event,
        job,
        replay: job.replayCount > 0,
      });
    } catch {
      await this.releaseClaim(jobId, claim.claimToken);
      return Err({
        code: 'config-unavailable',
        message: 'persisted delivery identity is invalid',
      });
    }
    const signature = this.signer.sign(deliveryBody, secret, signatureTimestampSeconds);
    const sent = await this.transport.send(
      withDeliveryAddressKind(
        {
          url: job.address,
          headers: outboundHeaders(signature.header),
          body: deliveryBody,
          ...(options.signal === undefined ? {} : { signal: options.signal }),
        },
        job.addressKind,
      ),
    );
    const transportError = (await sent.isErr()) ? await sent.unwrapErr() : null;
    const response = transportError === null ? await sent.unwrap() : null;
    if (aborted(options.signal) || transportError?.code === 'cancelled') {
      await this.releaseClaim(jobId, claim.claimToken);
      return Ok({ kind: 'skipped', jobId });
    }
    const recorded = await this.flow.recordAttempt(
      jobId,
      {
        number: attemptNumber,
        attemptedAtMs: nowMs,
        address: job.address,
        signatureTimestampSeconds,
        ...(response === null ? {} : { statusCode: response.status }),
        ...(transportError === null ? {} : { transportError: transportError.message }),
        replay: job.replayCount > 0,
      },
      claim.claimToken,
    );
    if (await recorded.isErr()) {
      return Err(storageFailure((await recorded.unwrapErr()).message));
    }
    const recordedJob = await recorded.unwrap();

    if (response?.status === 200) {
      const completed = await this.flow.completeJob(jobId, claim.claimToken);
      if (await completed.isErr()) {
        return Err(storageFailure((await completed.unwrapErr()).message));
      }
      const closed = await this.flow.closeCircuit(endpointKey);
      if (await closed.isErr()) {
        return Err(storageFailure((await closed.unwrapErr()).message));
      }
      if (circuit.status === 'open') {
        const resumed = await this.flow.resumeEndpoint(job.tenantId, job.endpointId, nowMs);
        if (await resumed.isErr()) {
          return Err(storageFailure((await resumed.unwrapErr()).message));
        }
        await this.telemetry.record({
          name: 'circuit.closed',
          attributes: {
            endpoint: job.endpointId,
            landscape: this.flow.landscape,
            tenant: job.tenantId,
          },
        });
      }
      await this.telemetry.record({
        name: 'delivery.success',
        attributes: {
          endpoint: job.endpointId,
          landscape: this.flow.landscape,
          tenant: job.tenantId,
        },
        value: Math.max(0, (nowMs - event.receivedAtMs) / 1_000),
      });
      return Ok({ kind: 'completed', jobId });
    }

    if (response?.status === 421 && job.misrouteRefreshes === 0) {
      await this.telemetry.record({
        name: 'stale-map',
        attributes: {
          endpoint: job.endpointId,
          landscape: this.flow.landscape,
          tenant: job.tenantId,
        },
      });
      const refreshed = await this.refresher.refreshEndpoint({
        tenantId: job.tenantId,
        routeId: job.routeId,
        endpointId: job.endpointId,
      });
      if (await refreshed.isOk()) {
        const endpoint = await refreshed.unwrap();
        const scheduled = await this.flow.scheduleJob(jobId, nowMs, endpoint.address, 1, claim.claimToken, true);
        if (await scheduled.isErr()) {
          return Err(storageFailure((await scheduled.unwrapErr()).message));
        }
        return this.processClaimed({ ...claim, job: await scheduled.unwrap() }, options);
      }
    }

    const circuitUpdate = await this.flow.recordEndpointFailure(endpointKey, nowMs, this.circuitFailureWindowMs);
    if (await circuitUpdate.isErr()) {
      await this.releaseClaim(jobId, claim.claimToken);
      return Err(storageFailure((await circuitUpdate.unwrapErr()).message));
    }
    const updatedCircuit = await circuitUpdate.unwrap();
    await this.telemetry.record({
      name: 'delivery.failure',
      attributes: {
        endpoint: job.endpointId,
        landscape: this.flow.landscape,
        status: response?.status ?? transportError?.code ?? 'unknown',
        tenant: job.tenantId,
      },
    });
    if (updatedCircuit.status === 'open') {
      const paused = await this.flow.pauseJob(jobId, claim.claimToken);
      if (await paused.isErr()) {
        return Err(storageFailure((await paused.unwrapErr()).message));
      }
      if (circuit.status !== 'open') {
        await this.telemetry.record({
          name: 'circuit.opened',
          attributes: {
            endpoint: job.endpointId,
            landscape: this.flow.landscape,
            tenant: job.tenantId,
          },
        });
      }
      return Ok({ kind: 'paused', jobId });
    }

    const retry = nextRetry({
      attemptNumber: recordedJob.attempts.length,
      createdAtMs: job.createdAtMs,
      nowMs,
      retryWindowMs: job.retryWindowMs,
    });
    if (retry.kind === 'dead-letter') {
      return this.moveToDeadLetter(
        job,
        nowMs,
        response === null ? 'transport failure' : `HTTP ${response.status}`,
        claim.claimToken,
      );
    }

    const scheduled = await this.flow.scheduleJob(jobId, retry.dueAtMs, undefined, undefined, claim.claimToken);
    if (await scheduled.isErr()) {
      return Err(storageFailure((await scheduled.unwrapErr()).message));
    }
    await this.telemetry.record({
      name: 'delivery.retry',
      attributes: {
        endpoint: job.endpointId,
        landscape: this.flow.landscape,
        tenant: job.tenantId,
      },
      value: 1,
    });
    return Ok({ dueAtMs: retry.dueAtMs, kind: 'retry', jobId });
  }

  async moveToDeadLetter(
    job: DeliveryJob,
    nowMs: number,
    reason: string,
    claimToken?: string,
  ): Promise<Result<DeliveryProcessOutcome, DeliveryFailure>> {
    const deadLetter = await this.flow.deadLetter(job.id, nowMs, reason, claimToken);
    if (await deadLetter.isErr()) {
      return Err(storageFailure((await deadLetter.unwrapErr()).message));
    }
    await this.telemetry.record({
      name: 'dlq.enqueued',
      attributes: {
        endpoint: job.endpointId,
        landscape: this.flow.landscape,
        tenant: job.tenantId,
      },
    });
    return Ok({ kind: 'dead-letter', jobId: job.id });
  }

  async runDue(
    nowMs: number,
    limit = 100,
    signal?: AbortSignal,
  ): Promise<readonly Result<DeliveryProcessOutcome, DeliveryFailure>[]> {
    if (aborted(signal)) {
      return [];
    }
    const expired = await this.flow.expirePausedJobs(nowMs, limit);
    if (await expired.isErr()) {
      return [Err(storageFailure((await expired.unwrapErr()).message))];
    }
    for (const entry of await expired.unwrap()) {
      await this.telemetry.record({
        name: 'dlq.enqueued',
        attributes: {
          endpoint: entry.endpointId,
          landscape: entry.landscape,
          tenant: entry.tenantId,
        },
      });
    }
    const claimed = await this.flow.claimDueJobs({
      claimToken: this.claimTokenFactory(),
      leaseMs: this.claimLeaseMs,
      limit,
      nowMs,
    });
    if (await claimed.isErr()) {
      return [Err(storageFailure((await claimed.unwrapErr()).message))];
    }
    const claims = await claimed.unwrap();
    return Promise.all(claims.map(claim => this.processClaimed(claim, signal === undefined ? {} : { signal })));
  }

  private async releaseClaim(jobId: string, claimToken: string): Promise<void> {
    try {
      await this.flow.releaseJobClaim(jobId, claimToken);
    } catch {
      // A failed release remains bounded by the durable lease expiry.
    }
  }

  async probe(jobId: string): Promise<Result<DeliveryProcessOutcome, DeliveryFailure>> {
    return this.process(jobId, { bypassCircuit: true });
  }

  async probeEndpoint(tenantId: string, endpointId: string): Promise<Result<boolean, DeliveryFailure>> {
    let cursor: string | undefined;
    for (let pageNumber = 0; pageNumber < 10; pageNumber += 1) {
      const page = await this.flow.listRetainedEvents({
        tenantId,
        endpointId,
        limit: 100,
        ...(cursor === undefined ? {} : { cursor }),
      });
      if (await page.isErr()) {
        return Err(storageFailure((await page.unwrapErr()).message));
      }
      const retained = await page.unwrap();
      const candidate = retained.items
        .flatMap(record => record.jobs)
        .find(job => job.endpointId === endpointId && (job.status === 'paused' || job.status === 'pending'));
      if (candidate !== undefined) {
        const outcome = await this.probe(candidate.id);
        return (await outcome.isErr())
          ? Err(await outcome.unwrapErr())
          : Ok((await outcome.unwrap()).kind === 'completed');
      }
      cursor = retained.nextCursor;
      if (cursor === undefined) {
        break;
      }
    }
    return Ok(false);
  }

  async manualClose(tenantId: string, endpointId: string): Promise<Result<void, DeliveryFailure>> {
    const closed = await this.flow.closeCircuit(deliveryEndpointKey(tenantId, endpointId));
    if (await closed.isErr()) {
      return Err(storageFailure((await closed.unwrapErr()).message));
    }
    const resumed = await this.flow.resumeEndpoint(tenantId, endpointId, this.clock.nowMs());
    if (await resumed.isErr()) {
      return Err(storageFailure((await resumed.unwrapErr()).message));
    }
    await this.telemetry.record({
      name: 'circuit.closed',
      attributes: {
        endpoint: endpointId,
        landscape: this.flow.landscape,
        tenant: tenantId,
      },
    });
    return Ok(undefined);
  }

  async replayEvent(eventId: string): Promise<Result<readonly DeliveryJob[], DeliveryFailure>> {
    const replayed = await this.flow.replayEvent(eventId, this.clock.nowMs());
    return (await replayed.isErr())
      ? Err(storageFailure((await replayed.unwrapErr()).message))
      : Ok(await replayed.unwrap());
  }

  async replayEndpoint(eventId: string, endpointId: string): Promise<Result<DeliveryJob, DeliveryFailure>> {
    const replayed = await this.flow.replayEndpoint(eventId, endpointId, this.clock.nowMs());
    return (await replayed.isErr())
      ? Err(storageFailure((await replayed.unwrapErr()).message))
      : Ok(await replayed.unwrap());
  }

  async replayEndpointFailures(
    tenantId: string,
    endpointId: string,
  ): Promise<Result<readonly DeliveryJob[], DeliveryFailure>> {
    const replayed = await this.flow.replayDeadLettersForEndpoint(tenantId, endpointId, this.clock.nowMs());
    return (await replayed.isErr())
      ? Err(storageFailure((await replayed.unwrapErr()).message))
      : Ok(await replayed.unwrap());
  }
}
