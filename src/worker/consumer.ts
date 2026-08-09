import type { OtelRuntime } from '@atomicloud/diene.e2e/otel';
import type { RedisStreamsTransport } from '../adapters/redis-streams';
import type { SampleWorkerHandler } from '../domain/handler';
import type { FileHeartbeat } from '../health/heartbeat';
import { decodeWorkerMessage, type StreamEnvelope } from '../lib/message-codec';
import { requireResult } from '../init/result';

export class ConsumerWorker {
  constructor(
    readonly transport: RedisStreamsTransport,
    readonly handler: SampleWorkerHandler,
    readonly heartbeat: FileHeartbeat,
    readonly telemetry: OtelRuntime,
    readonly maxMessageBytes: number,
    readonly identityAttributes: Readonly<Record<string, string>>,
  ) {}

  async refreshHeartbeat(state: 'healthy' | 'starting' | 'stopping'): Promise<void> {
    await this.heartbeat.write(state);
    await this.telemetry.metricsCollector
      .record({
        attributes: { ...this.identityAttributes, 'atomi.worker.state': state },
        kind: 'gauge',
        name: 'atomi.worker.health',
        value: state === 'healthy' ? 1 : 0,
      })
      .match({
        err: error => this.telemetry.logger.warn({ error }, 'worker health metric failed'),
        ok: () => undefined,
      });
  }

  async processEnvelope(envelope: StreamEnvelope): Promise<boolean> {
    try {
      if (Buffer.byteLength(envelope.payload) > this.maxMessageBytes)
        throw new Error('message exceeds configured limit');
      const message = decodeWorkerMessage(envelope.payload);
      return await this.handler.handle(message).match({
        err: error => {
          this.telemetry.logger.error({ error, messageId: message.id }, 'message handling failed');
          return false;
        },
        ok: result => {
          this.telemetry.logger.info({ messageId: message.id, ...result }, 'message handled');
          return true;
        },
      });
    } catch (error) {
      this.telemetry.logger.error({ error, streamId: envelope.id }, 'invalid worker message');
      return true;
    }
  }

  async processBatch(envelopes: readonly StreamEnvelope[]): Promise<number> {
    let acknowledged = 0;
    for (const envelope of envelopes) {
      if (await this.processEnvelope(envelope)) {
        acknowledged += await requireResult(this.transport.acknowledge(envelope.id));
      }
    }
    return acknowledged;
  }

  async run(signal: AbortSignal, once = false): Promise<void> {
    await this.refreshHeartbeat('starting');
    await requireResult(this.transport.ensureGroup());
    await this.processBatch(await requireResult(this.transport.reclaimPending()));
    do {
      await this.processBatch(await requireResult(this.transport.consume()));
      await this.refreshHeartbeat('healthy');
    } while (!once && !signal.aborted);
    if (!once) await this.refreshHeartbeat('stopping');
  }
}
