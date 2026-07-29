import { describe, it } from 'bun:test';
import { Ok, type Result } from '@atomicloud/diene.result';
import should from 'should';
import type { ArchiveFailure, WebhookEnvelope } from '../../../src/domain/index.ts';
import { ManualClock, MemoryTelemetry } from '../../../src/runtime/fakes.ts';
import {
  EventRetentionManager,
  MemoryArchiveStore,
  TigrisArchiveStore,
  type TigrisObjectClient,
} from '../../../src/storage/archive.ts';
import { MemoryLandscapeStore } from '../../../src/storage/memory.ts';

const encoder = new TextEncoder();
const decoder = new TextDecoder();

class InspectableTigrisClient implements TigrisObjectClient {
  public corruptReadBack = false;
  readonly objects = new Map<string, Uint8Array>();
  public heads = 0;
  public reads = 0;

  async putObject(request: {
    readonly bucket: string;
    readonly key: string;
    readonly body: Uint8Array;
    readonly contentType: 'application/json';
  }): Promise<Result<void, ArchiveFailure>> {
    this.objects.set(`${request.bucket}:${request.key}`, request.body.slice());
    return Ok(undefined);
  }

  async headObject(request: {
    readonly bucket: string;
    readonly key: string;
  }): Promise<Result<Readonly<{ byteLength: number; storageTag?: string }>, ArchiveFailure>> {
    this.heads += 1;
    return Ok({
      byteLength: this.objects.get(`${request.bucket}:${request.key}`)?.byteLength ?? 0,
      storageTag: 'tigris-etag',
    });
  }

  async readObject(request: {
    readonly bucket: string;
    readonly key: string;
  }): Promise<Result<Uint8Array, ArchiveFailure>> {
    this.reads += 1;
    const body = this.objects.get(`${request.bucket}:${request.key}`)?.slice() ?? new Uint8Array();
    if (this.corruptReadBack && body.byteLength > 0) {
      body[0] = (body[0] ?? 0) ^ 0xff;
    }
    return Ok(body);
  }
}

const seedMonth = async (store: MemoryLandscapeStore, receivedAtMs: number, eventId: string): Promise<void> => {
  const envelope: WebhookEnvelope = {
    id: eventId,
    tenantId: 'external/acme',
    routeId: 'retained',
    provider: 'stripe',
    landingLandscape: store.landscape,
    receivedAtMs,
    providerEventId: eventId,
    dedupId: eventId,
    rawBody: encoder.encode(`{"id":"${eventId}"}`),
    headers: { 'content-type': 'application/json' },
    verificationMetadata: {},
    obligations: [],
  };
  await (
    await store.acceptOnce({
      dedupKey: `dedup:external%2Facme:retained:${eventId}`,
      dedupTtlSeconds: 72 * 60 * 60,
      envelope,
      jobs: [],
    })
  ).unwrap();
};

describe('EventRetentionManager', () => {
  it('should archive the aging month to Tigris storage before retaining exactly two live partitions', async () => {
    // Arrange
    const clock = new ManualClock(Date.UTC(2026, 2, 15));
    const flow = new MemoryLandscapeStore('raichu', clock);
    await seedMonth(flow, Date.UTC(2026, 0, 15), 'event-january');
    await seedMonth(flow, Date.UTC(2026, 1, 15), 'event-february');
    await seedMonth(flow, Date.UTC(2026, 2, 15), 'event-march');
    const archive = new MemoryArchiveStore();
    const telemetry = new MemoryTelemetry();
    const subject = new EventRetentionManager(flow, archive, clock, telemetry);

    // Act
    const actual = await (await subject.rollover('external/acme')).unwrap();
    const part = archive.objects.get('raichu:external/acme:2026-01/versions/1/parts/00000000');
    const manifest = archive.objects.get('raichu:external/acme:2026-01/versions/1/manifest');
    const partPayload = part === undefined ? null : (JSON.parse(decoder.decode(part.body)) as { records: unknown[] });
    const manifestPayload =
      manifest === undefined
        ? null
        : (JSON.parse(decoder.decode(manifest.body)) as { partCount: number; eventCount: number });

    // Assert
    should(actual.archivedMonths).deepEqual(['2026-01']);
    should(actual.liveMonths).deepEqual(['2026-02', '2026-03']);
    should(part).not.be.undefined();
    should(manifest).not.be.undefined();
    should(partPayload?.records).have.length(1);
    should(manifestPayload?.partCount).equal(1);
    should(manifestPayload?.eventCount).equal(1);
    should(telemetry.events.map(event => event.name)).containEql('archive.success');
  });

  it('should archive a sparse UTC-old month even when only two calendar partitions exist', async () => {
    // Arrange
    const clock = new ManualClock(Date.UTC(2026, 2, 15));
    const flow = new MemoryLandscapeStore('raichu', clock);
    await seedMonth(flow, Date.UTC(2026, 0, 31, 23, 59, 59), 'event-january-edge');
    await seedMonth(flow, Date.UTC(2026, 2, 1), 'event-march');
    const archive = new MemoryArchiveStore();
    const subject = new EventRetentionManager(flow, archive, clock, new MemoryTelemetry());

    // Act
    const actual = await (await subject.rollover('external/acme')).unwrap();

    // Assert
    should(actual.archivedMonths).deepEqual(['2026-01']);
    should(actual.liveMonths).deepEqual(['2026-03']);
    should(archive.objects.has('raichu:external/acme:2026-01/versions/1/manifest')).be.true();
  });

  it('should cap every archive part and page a multi-event month under the configured record bound', async () => {
    // Arrange
    const clock = new ManualClock(Date.UTC(2026, 2, 15));
    const flow = new MemoryLandscapeStore('raichu', clock);
    for (let index = 1; index <= 5; index += 1) {
      await seedMonth(flow, Date.UTC(2026, 0, index), `event-january-${index}`);
    }
    await seedMonth(flow, Date.UTC(2026, 2, 1), 'event-march');
    const archive = new MemoryArchiveStore();
    const telemetry = new MemoryTelemetry();
    const maxPartBytes = 16 * 1_024;
    const subject = new EventRetentionManager(flow, archive, clock, telemetry, 2, 2, maxPartBytes, 2);

    // Act
    const actual = await (await subject.rollover('external/acme')).unwrap();
    const parts = [...archive.objects]
      .filter(([key]) => key.includes('2026-01/versions/5/parts/'))
      .map(([, object]) => object);
    const manifest = archive.objects.get('raichu:external/acme:2026-01/versions/5/manifest');
    const manifestPayload =
      manifest === undefined
        ? null
        : (JSON.parse(decoder.decode(manifest.body)) as { eventCount: number; partCount: number });

    // Assert
    should(actual.archivedMonths).deepEqual(['2026-01']);
    should(actual.liveMonths).deepEqual(['2026-03']);
    should(parts).have.length(3);
    should(parts.every(part => part.body.byteLength <= maxPartBytes)).be.true();
    should(manifestPayload?.partCount).equal(3);
    should(manifestPayload?.eventCount).equal(5);
    should(flow.events.size).equal(1);
    should(telemetry.events.map(event => event.name)).containEql('archive.success');
  });

  it('should alert and block deletion when the archive upload fails', async () => {
    // Arrange
    const clock = new ManualClock(Date.UTC(2026, 2, 15));
    const flow = new MemoryLandscapeStore('ampharos', clock);
    await seedMonth(flow, Date.UTC(2026, 0, 15), 'event-january');
    await seedMonth(flow, Date.UTC(2026, 1, 15), 'event-february');
    await seedMonth(flow, Date.UTC(2026, 2, 15), 'event-march');
    const archive = new MemoryArchiveStore();
    archive.failingMonths.add('2026-01');
    const telemetry = new MemoryTelemetry();
    const subject = new EventRetentionManager(flow, archive, clock, telemetry);

    // Act
    const actual = await subject.rollover('external/acme');
    const liveMonths = await (await flow.listEventMonths('external/acme')).unwrap();

    // Assert
    should(await actual.isErr()).be.true();
    should(liveMonths).deepEqual(['2026-01', '2026-02', '2026-03']);
    should(archive.objects.size).equal(0);
    should(telemetry.events.map(event => event.name)).containEql('archive.failure');
  });

  it('should require Tigris head, size, and digest read-back before deleting Redis data', async () => {
    // Arrange
    const clock = new ManualClock(Date.UTC(2026, 2, 15));
    const flow = new MemoryLandscapeStore('raichu', clock);
    await seedMonth(flow, Date.UTC(2026, 0, 15), 'event-january');
    await seedMonth(flow, Date.UTC(2026, 1, 15), 'event-february');
    await seedMonth(flow, Date.UTC(2026, 2, 15), 'event-march');
    const client = new InspectableTigrisClient();
    client.corruptReadBack = true;
    const telemetry = new MemoryTelemetry();
    const subject = new EventRetentionManager(
      flow,
      new TigrisArchiveStore('mercury-archive', client),
      clock,
      telemetry,
    );

    // Act
    const result = await subject.rollover('external/acme');
    const months = await (await flow.listEventMonths('external/acme')).unwrap();

    // Assert
    should(await result.isErr()).be.true();
    should(client.heads).equal(1);
    should(client.reads).equal(1);
    should(months).deepEqual(['2026-01', '2026-02', '2026-03']);
    should(telemetry.events.map(event => event.name)).containEql('archive.failure');
  });

  it('should write verified production Tigris parts and manifest under a fenced version path', async () => {
    // Arrange
    const clock = new ManualClock(Date.UTC(2026, 2, 15));
    const flow = new MemoryLandscapeStore('raichu', clock);
    await seedMonth(flow, Date.UTC(2026, 0, 15), 'event-january');
    const client = new InspectableTigrisClient();
    const subject = new EventRetentionManager(
      flow,
      new TigrisArchiveStore('mercury-archive', client),
      clock,
      new MemoryTelemetry(),
    );

    // Act
    const actual = await (await subject.rollover('external/acme')).unwrap();

    // Assert
    should(actual.archivedMonths).deepEqual(['2026-01']);
    should(client.heads).equal(2);
    should(client.reads).equal(2);
    should(
      client.objects.has('mercury-archive:raichu/external%2Facme/2026-01/versions/1/parts/00000000.json'),
    ).be.true();
    should(client.objects.has('mercury-archive:raichu/external%2Facme/2026-01/versions/1/manifest.json')).be.true();
  });
});
