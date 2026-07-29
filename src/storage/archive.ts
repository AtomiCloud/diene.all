import { createHash, randomUUID } from 'node:crypto';
import { Err, Ok, type Result } from '@atomicloud/diene.result';
import type {
  ArchiveFailure,
  ArchiveObject,
  ArchiveReceipt,
  ArchiveStore,
  Clock,
  FlowStore,
  RuntimeTelemetry,
  StorageFailure,
} from '../domain/index.ts';

export interface TigrisObjectClient {
  putObject(request: {
    readonly bucket: string;
    readonly key: string;
    readonly body: Uint8Array;
    readonly contentType: 'application/json';
  }): Promise<Result<void, ArchiveFailure>>;
  headObject(request: {
    readonly bucket: string;
    readonly key: string;
  }): Promise<Result<Readonly<{ byteLength: number; storageTag?: string }>, ArchiveFailure>>;
  readObject(request: { readonly bucket: string; readonly key: string }): Promise<Result<Uint8Array, ArchiveFailure>>;
}

export interface BunTigrisClientConfig {
  readonly endpoint: string;
  readonly region: string;
  readonly accessKeyId: string;
  readonly secretAccessKey: string;
  readonly sessionToken?: string;
}

/** Production Tigris sink using Bun's S3-compatible client. */
class BunTigrisObjectClient implements TigrisObjectClient {
  constructor(readonly client: Bun.S3Client) {}

  async putObject(request: {
    readonly bucket: string;
    readonly key: string;
    readonly body: Uint8Array;
    readonly contentType: 'application/json';
  }): Promise<Result<void, ArchiveFailure>> {
    try {
      await this.client.write(request.key, request.body, {
        bucket: request.bucket,
        type: request.contentType,
      });
      return Ok(undefined);
    } catch (error) {
      return Err({
        code: 'unavailable',
        message: error instanceof Error ? error.message : 'Tigris upload failed',
      });
    }
  }

  async headObject(request: {
    readonly bucket: string;
    readonly key: string;
  }): Promise<Result<Readonly<{ byteLength: number; storageTag?: string }>, ArchiveFailure>> {
    try {
      const stat = await this.client.stat(request.key, {
        bucket: request.bucket,
      });
      return Ok({
        byteLength: stat.size,
        ...(stat.etag.length === 0 ? {} : { storageTag: stat.etag }),
      });
    } catch (error) {
      return Err({
        code: 'unavailable',
        message: error instanceof Error ? error.message : 'Tigris head failed',
      });
    }
  }

  async readObject(request: {
    readonly bucket: string;
    readonly key: string;
  }): Promise<Result<Uint8Array, ArchiveFailure>> {
    try {
      return Ok(await this.client.file(request.key, { bucket: request.bucket }).bytes());
    } catch (error) {
      return Err({
        code: 'unavailable',
        message: error instanceof Error ? error.message : 'Tigris read-back failed',
      });
    }
  }
}

const sha256 = (body: Uint8Array): string => createHash('sha256').update(body).digest('hex');

const verificationFailure = (message: string): ArchiveFailure => ({
  code: 'unavailable',
  message,
});

/** Thin Tigris adapter; auth/signing stays in the injected object client. */
export class TigrisArchiveStore implements ArchiveStore {
  constructor(
    readonly bucket: string,
    readonly client: TigrisObjectClient,
  ) {}

  async put(object: ArchiveObject): Promise<Result<ArchiveReceipt, ArchiveFailure>> {
    const key = `${encodeURIComponent(object.landscape)}/${encodeURIComponent(object.tenantId)}/${object.month}.json`;
    const expected: ArchiveReceipt = {
      byteLength: object.body.byteLength,
      sha256: sha256(object.body),
    };
    const uploaded = await this.client.putObject({
      bucket: this.bucket,
      key,
      body: object.body,
      contentType: 'application/json',
    });
    if (await uploaded.isErr()) {
      return Err(await uploaded.unwrapErr());
    }
    const head = await this.client.headObject({ bucket: this.bucket, key });
    if (await head.isErr()) {
      return Err(await head.unwrapErr());
    }
    const metadata = await head.unwrap();
    if (metadata.byteLength !== expected.byteLength) {
      return Err(verificationFailure('Tigris archive size verification failed'));
    }
    const readBack = await this.client.readObject({ bucket: this.bucket, key });
    if (await readBack.isErr()) {
      return Err(await readBack.unwrapErr());
    }
    const persisted = await readBack.unwrap();
    if (persisted.byteLength !== expected.byteLength || sha256(persisted) !== expected.sha256) {
      return Err(verificationFailure('Tigris archive digest verification failed'));
    }
    return Ok({
      ...expected,
      ...(metadata.storageTag === undefined ? {} : { storageTag: metadata.storageTag }),
    });
  }
}

export const createTigrisArchiveStore = (bucket: string, config: BunTigrisClientConfig): TigrisArchiveStore => {
  const client = new Bun.S3Client({
    endpoint: config.endpoint,
    region: config.region,
    accessKeyId: config.accessKeyId,
    secretAccessKey: config.secretAccessKey,
    ...(config.sessionToken === undefined ? {} : { sessionToken: config.sessionToken }),
  });
  return new TigrisArchiveStore(bucket, new BunTigrisObjectClient(client));
};

export class MemoryArchiveStore implements ArchiveStore {
  readonly objects = new Map<string, ArchiveObject>();
  readonly failingMonths = new Set<string>();
  readonly writes: string[] = [];

  async put(object: ArchiveObject): Promise<Result<ArchiveReceipt, ArchiveFailure>> {
    const key = `${object.landscape}:${object.tenantId}:${object.month}`;
    this.writes.push(key);
    const calendarMonth = object.month.split('/')[0] ?? object.month;
    if (this.failingMonths.has(calendarMonth)) {
      return Err({
        code: 'unavailable',
        message: `archive unavailable for ${calendarMonth}`,
      });
    }
    this.objects.set(key, { ...object, body: object.body.slice() });
    return Ok({
      byteLength: object.body.byteLength,
      sha256: sha256(object.body),
    });
  }
}

export interface RetentionResult {
  readonly archivedMonths: readonly string[];
  readonly liveMonths: readonly string[];
}

const retentionFailure = (operation: string, message: string): StorageFailure => ({
  code: 'invalid-data',
  operation,
  message,
});

const calendarCutoffMonth = (nowMs: number, keepMonths: number): string => {
  const now = new Date(nowMs);
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - (keepMonths - 1), 1)).toISOString().slice(0, 7);
};

const archiveFailureEvent = async (
  telemetry: RuntimeTelemetry,
  landscape: string,
  tenantId: string,
  month: string,
): Promise<void> =>
  telemetry.record({
    name: 'archive.failure',
    attributes: { landscape, month, tenant: tenantId },
  });

export class EventRetentionManager {
  constructor(
    readonly flow: FlowStore,
    readonly archive: ArchiveStore,
    readonly clock: Clock,
    readonly telemetry: RuntimeTelemetry,
    readonly keepMonths = 2,
    readonly pageLimit = 100,
    readonly maxPartBytes = 4 * 1_024 * 1_024,
    readonly deletionLimit = 100,
    readonly leaseMs = 5 * 60 * 1_000,
    readonly leaseToken: () => string = randomUUID,
  ) {
    for (const value of [keepMonths, pageLimit, maxPartBytes, deletionLimit, leaseMs]) {
      if (!Number.isSafeInteger(value) || value < 1) {
        throw new RangeError('retention bounds must be positive safe integers');
      }
    }
    if (pageLimit > 1_000 || deletionLimit > 1_000) {
      throw new RangeError('retention page bounds may not exceed 1,000 records');
    }
  }

  async rollover(tenantId: string): Promise<Result<RetentionResult, ArchiveFailure | StorageFailure>> {
    const monthsResult = await this.flow.listEventMonths(tenantId);
    if (await monthsResult.isErr()) {
      return Err(await monthsResult.unwrapErr());
    }
    const months = [...(await monthsResult.unwrap())].sort();
    const cutoffMonth = calendarCutoffMonth(this.clock.nowMs(), this.keepMonths);
    const aging = months.filter(month => month < cutoffMonth);
    const archived: string[] = [];

    for (const month of aging) {
      const begun = await this.flow.beginEventMonthArchive({
        tenantId,
        month,
        leaseToken: this.leaseToken(),
        nowMs: this.clock.nowMs(),
        leaseMs: this.leaseMs,
      });
      if (await begun.isErr()) {
        return Err(await begun.unwrapErr());
      }
      let lease = await begun.unwrap();
      let manifest = lease.manifest;

      if (lease.phase === 'exporting') {
        const versionRoot = `${month}/versions/${String(lease.version)}`;
        const partsDigest = createHash('sha256');
        let cursor: string | undefined;
        let partCount = 0;
        let eventCount = 0;
        let jobCount = 0;
        let deadLetterCount = 0;
        let archiveByteLength = 0;

        while (true) {
          const renewed = await this.flow.renewEventMonthArchive(lease, this.clock.nowMs(), this.leaseMs);
          if (await renewed.isErr()) {
            await this.flow.abortEventMonthArchive(lease);
            return Err(await renewed.unwrapErr());
          }
          lease = await renewed.unwrap();
          const page = await this.flow.readEventMonthArchivePage(lease, cursor, this.pageLimit, this.maxPartBytes);
          if (await page.isErr()) {
            await this.flow.abortEventMonthArchive(lease);
            return Err(await page.unwrapErr());
          }
          const part = await page.unwrap();
          if (part.eventCount === 0) {
            break;
          }
          const objectPath = `${versionRoot}/parts/${String(partCount).padStart(8, '0')}`;
          const stored = await this.archive.put({
            landscape: this.flow.landscape,
            tenantId,
            month: objectPath,
            body: part.body,
          });
          if (await stored.isErr()) {
            const archiveFailure = await stored.unwrapErr();
            await this.flow.abortEventMonthArchive(lease);
            await archiveFailureEvent(this.telemetry, this.flow.landscape, tenantId, month);
            return Err(archiveFailure);
          }
          const receipt = await stored.unwrap();
          partsDigest.update(
            `${JSON.stringify({
              objectPath,
              part: partCount,
              byteLength: receipt.byteLength,
              sha256: receipt.sha256,
              firstCursor: part.firstCursor,
              lastCursor: part.lastCursor,
            })}\n`,
          );
          archiveByteLength += receipt.byteLength;
          eventCount += part.eventCount;
          jobCount += part.jobCount;
          deadLetterCount += part.deadLetterCount;
          partCount += 1;
          cursor = part.nextCursor;
          if (cursor === undefined) {
            break;
          }
        }

        const partsSha256 = partsDigest.digest('hex');
        const manifestBody = new TextEncoder().encode(
          JSON.stringify({
            schema: 'mercury.event-archive-manifest.v1',
            landscape: this.flow.landscape,
            tenantId,
            month,
            version: lease.version,
            snapshotCursor: lease.snapshotCursor,
            partCount,
            partsSha256,
            eventCount,
            jobCount,
            deadLetterCount,
            archiveByteLength,
          }),
        );
        if (manifestBody.byteLength > this.maxPartBytes) {
          await this.flow.abortEventMonthArchive(lease);
          return Err(retentionFailure('archive-event-month', 'archive manifest exceeds the configured part bound'));
        }
        const objectPath = `${versionRoot}/manifest`;
        const manifestStored = await this.archive.put({
          landscape: this.flow.landscape,
          tenantId,
          month: objectPath,
          body: manifestBody,
        });
        if (await manifestStored.isErr()) {
          const archiveFailure = await manifestStored.unwrapErr();
          await this.flow.abortEventMonthArchive(lease);
          await archiveFailureEvent(this.telemetry, this.flow.landscape, tenantId, month);
          return Err(archiveFailure);
        }
        const manifestReceipt = await manifestStored.unwrap();
        manifest = {
          objectPath,
          byteLength: manifestReceipt.byteLength,
          sha256: manifestReceipt.sha256,
          partCount,
          partsSha256,
          eventCount,
          jobCount,
          deadLetterCount,
          archiveByteLength: archiveByteLength + manifestReceipt.byteLength,
        };
        const renewed = await this.flow.renewEventMonthArchive(lease, this.clock.nowMs(), this.leaseMs);
        if (await renewed.isErr()) {
          await this.flow.abortEventMonthArchive(lease);
          return Err(await renewed.unwrapErr());
        }
        lease = await renewed.unwrap();
        const sealed = await this.flow.sealEventMonthArchive(lease, manifest);
        if (await sealed.isErr()) {
          await this.flow.abortEventMonthArchive(lease);
          return Err(await sealed.unwrapErr());
        }
        lease = await sealed.unwrap();
      }

      if (manifest === undefined || lease.phase !== 'deleting') {
        return Err(retentionFailure('archive-event-month', 'sealed archive manifest is unavailable'));
      }
      while (true) {
        const renewed = await this.flow.renewEventMonthArchive(lease, this.clock.nowMs(), this.leaseMs);
        if (await renewed.isErr()) {
          return Err(await renewed.unwrapErr());
        }
        lease = await renewed.unwrap();
        const deleted = await this.flow.deleteEventMonthArchivePage(lease, this.deletionLimit);
        if (await deleted.isErr()) {
          return Err(await deleted.unwrapErr());
        }
        if ((await deleted.unwrap()).done) {
          break;
        }
      }
      const completed = await this.flow.completeEventMonthArchive(lease);
      if (await completed.isErr()) {
        return Err(await completed.unwrapErr());
      }
      archived.push(month);
      await this.telemetry.record({
        name: 'archive.success',
        attributes: {
          bytes: manifest.archiveByteLength,
          landscape: this.flow.landscape,
          month,
          tenant: tenantId,
          timestamp: this.clock.nowMs(),
        },
      });
    }

    const remaining = await this.flow.listEventMonths(tenantId);
    if (await remaining.isErr()) {
      return Err(await remaining.unwrapErr());
    }
    return Ok({
      archivedMonths: archived,
      liveMonths: await remaining.unwrap(),
    });
  }
}
