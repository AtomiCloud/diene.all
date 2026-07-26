import { Err, Ok, Res, type Result } from '@atomicloud/diene.e2e/result';
import type Redis from 'ioredis';
import type { ApplicationConfig } from '../config/schema';
import { decodeAutoClaimResponse, decodeReadGroupResponse, type StreamEnvelope } from '../lib/message-codec';
import { AdapterError } from './error';
import { type ApplicationTracer, withAdapterSpan } from './tracing';

export class RedisStreamsTransport {
  constructor(
    readonly client: Redis,
    readonly tracer: ApplicationTracer,
    readonly config: ApplicationConfig['transport'],
  ) {}

  ensureGroup(): Result<void, AdapterError> {
    return Res.async(async () => {
      try {
        await withAdapterSpan(
          this.tracer,
          'messaging.redis.create_consumer_group',
          { 'atomi.transport': 'redis-streams', 'messaging.destination.name': this.config.stream },
          () => this.client.xgroup('CREATE', this.config.stream, this.config.consumerGroup, '0', 'MKSTREAM'),
        );
        return Ok(undefined);
      } catch (error) {
        if (error instanceof Error && error.message.includes('BUSYGROUP')) return Ok(undefined);
        return Err(new AdapterError('redis-streams.ensure-group', 'consumer group creation failed', error));
      }
    });
  }

  publish(payload: string): Result<string, AdapterError> {
    return Res.async(async () => {
      try {
        const id = await withAdapterSpan(
          this.tracer,
          'messaging.redis.publish',
          { 'atomi.transport': 'redis-streams', 'messaging.destination.name': this.config.stream },
          () => this.client.xadd(this.config.stream, '*', 'payload', payload),
        );
        return Ok(id ?? '');
      } catch (error) {
        return Err(new AdapterError('redis-streams.publish', 'stream publish failed', error));
      }
    });
  }

  consume(): Result<readonly StreamEnvelope[], AdapterError> {
    return Res.async(async () => {
      try {
        const response = await withAdapterSpan(
          this.tracer,
          'messaging.redis.receive',
          { 'atomi.transport': 'redis-streams', 'messaging.destination.name': this.config.stream },
          () =>
            this.client.xreadgroup(
              'GROUP',
              this.config.consumerGroup,
              this.config.consumerName,
              'COUNT',
              this.config.batchSize,
              'BLOCK',
              this.config.blockMs,
              'STREAMS',
              this.config.stream,
              '>',
            ),
        );
        return Ok(decodeReadGroupResponse(response));
      } catch (error) {
        return Err(new AdapterError('redis-streams.consume', 'stream consume failed', error));
      }
    });
  }

  reclaimPending(): Result<readonly StreamEnvelope[], AdapterError> {
    return Res.async(async () => {
      try {
        const response = await withAdapterSpan(
          this.tracer,
          'messaging.redis.reclaim',
          { 'atomi.transport': 'redis-streams', 'messaging.destination.name': this.config.stream },
          () =>
            this.client.xautoclaim(
              this.config.stream,
              this.config.consumerGroup,
              this.config.consumerName,
              this.config.idleMs,
              '0-0',
              'COUNT',
              this.config.batchSize,
            ),
        );
        return Ok(decodeAutoClaimResponse(response));
      } catch (error) {
        return Err(new AdapterError('redis-streams.reclaim', 'pending stream reclaim failed', error));
      }
    });
  }

  acknowledge(id: string): Result<number, AdapterError> {
    return Res.async(async () => {
      try {
        const count = await withAdapterSpan(
          this.tracer,
          'messaging.redis.acknowledge',
          { 'atomi.transport': 'redis-streams', 'messaging.destination.name': this.config.stream },
          () => this.client.xack(this.config.stream, this.config.consumerGroup, id),
        );
        return Ok(count);
      } catch (error) {
        return Err(new AdapterError('redis-streams.acknowledge', 'stream acknowledgement failed', error));
      }
    });
  }
}
