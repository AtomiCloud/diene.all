import type {
  DeliveryJob,
  RetainedEventQuery,
  RetainedEventRecord,
  RetainedEventStatus,
  WebhookEnvelope,
} from '../domain/index.ts';

const retainedEventStatus = (jobs: readonly DeliveryJob[]): RetainedEventStatus => {
  if (jobs.some(job => job.status === 'dead-letter')) {
    return 'dead-letter';
  }
  if (jobs.some(job => job.status === 'paused')) {
    return 'paused';
  }
  if (jobs.length === 0 || jobs.every(job => job.status === 'completed')) {
    return 'completed';
  }
  if (jobs.some(job => job.attempts.length > 0)) {
    return 'retrying';
  }
  return 'pending';
};

export const retainedEventRecord = (envelope: WebhookEnvelope, jobs: readonly DeliveryJob[]): RetainedEventRecord => ({
  envelope,
  jobs,
  status: retainedEventStatus(jobs),
});

export const retainedEventMatches = (record: RetainedEventRecord, query: RetainedEventQuery): boolean =>
  (query.provider === undefined || record.envelope.provider === query.provider) &&
  (query.routeId === undefined || record.envelope.routeId === query.routeId) &&
  (query.endpointId === undefined || record.jobs.some(job => job.endpointId === query.endpointId)) &&
  (query.status === undefined || record.status === query.status) &&
  (query.receivedAfterMs === undefined || record.envelope.receivedAtMs >= query.receivedAfterMs) &&
  (query.receivedBeforeMs === undefined || record.envelope.receivedAtMs <= query.receivedBeforeMs);

export const retainedEventOffset = (cursor: string | undefined): number | null => {
  if (cursor === undefined) {
    return 0;
  }
  if (!/^(0|[1-9]\d*)$/.test(cursor)) {
    return null;
  }
  const offset = Number(cursor);
  return Number.isSafeInteger(offset) ? offset : null;
};

export const retainedEventLimit = (limit: number | undefined): number | null => {
  const selected = limit ?? 50;
  return Number.isSafeInteger(selected) && selected >= 1 && selected <= 200 ? selected : null;
};
