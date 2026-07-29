import type { DeadLetterEntry, DeliveryJob, LandscapeRuntimeConfig, WebhookEnvelope } from '../domain/index.ts';

interface StoredEnvelope extends Omit<WebhookEnvelope, 'rawBody'> {
  readonly rawBodyBase64: string;
}

export const encodeEnvelope = (envelope: WebhookEnvelope): string =>
  JSON.stringify({
    ...envelope,
    rawBody: undefined,
    rawBodyBase64: Buffer.from(envelope.rawBody).toString('base64'),
  } satisfies StoredEnvelope & { readonly rawBody?: undefined });

export const decodeEnvelope = (value: string): WebhookEnvelope => {
  const parsed = JSON.parse(value) as StoredEnvelope;
  return {
    ...parsed,
    rawBody: Uint8Array.from(Buffer.from(parsed.rawBodyBase64, 'base64')),
  };
};

export const encodeJob = (job: DeliveryJob): string => JSON.stringify(job);

export const decodeJob = (value: string): DeliveryJob => JSON.parse(value) as DeliveryJob;

export const encodeRuntimeConfig = (config: LandscapeRuntimeConfig): string => JSON.stringify(config);

export const decodeRuntimeConfig = (value: string): LandscapeRuntimeConfig =>
  JSON.parse(value) as LandscapeRuntimeConfig;

export interface EventArchiveRecord {
  readonly envelope: WebhookEnvelope;
  readonly jobs: readonly DeliveryJob[];
  readonly deadLetters: readonly DeadLetterEntry[];
}

export const encodeEventArchivePage = (
  landscape: string,
  tenantId: string,
  month: string,
  version: number,
  records: readonly EventArchiveRecord[],
): Uint8Array =>
  new TextEncoder().encode(
    JSON.stringify({
      schema: 'mercury.event-archive-part.v1',
      landscape,
      tenantId,
      month,
      version,
      records: records.map(record => ({
        envelope: JSON.parse(encodeEnvelope(record.envelope)) as unknown,
        jobs: record.jobs,
        deadLetters: record.deadLetters,
      })),
    }),
  );

export const eventMonth = (receivedAtMs: number): string => new Date(receivedAtMs).toISOString().slice(0, 7);
