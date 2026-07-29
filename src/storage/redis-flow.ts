import { Err, Ok, type Result } from '@atomicloud/diene.result';
import type Redis from 'ioredis';
import type {
  AtomicAcceptOutcome,
  AtomicAcceptRequest,
  BeginEventMonthArchiveRequest,
  CircuitStatus,
  DeadLetterEntry,
  DeadLetterPage,
  DeliveryAttempt,
  DeliveryClaimRequest,
  DeliveryJob,
  DeliveryJobClaim,
  EndpointCircuit,
  EventMonthArchiveLease,
  EventMonthArchiveManifest,
  EventMonthArchivePage,
  EventMonthDeletionPage,
  FlowStore,
  QuotaDecision,
  QuotaRequest,
  RetainedEventPage,
  RetainedEventQuery,
  StorageFailure,
  WebhookEnvelope,
} from '../domain/index.ts';
import {
  decodeEnvelope,
  decodeJob,
  type EventArchiveRecord,
  encodeEnvelope,
  encodeEventArchivePage,
  encodeJob,
  eventMonth,
} from './codec.ts';
import {
  retainedEventLimit,
  retainedEventMatches,
  retainedEventOffset,
  retainedEventRecord,
} from './retained-events.ts';

const READY_QUEUE_KEY = 'q:deliver:ready';
const RETRY_QUEUE_KEY = 'q:retry';
const DELIVERY_CLAIMS_KEY = 'q:deliver:claims';
const DELIVERY_CLAIM_EXPIRIES_KEY = 'q:deliver:claim-expiries';
const PAUSED_EXPIRIES_KEY = 'q:paused:expiries';
const DLQ_FIELD_EXPIRY_PROBE_KEY = 'dlq:field-expiry-probe';
const MAX_DLQ_RETENTION_MS = 72 * 60 * 60 * 1_000;
const DEFAULT_PAGE_LIMIT = 100;
const MAX_PAGE_LIMIT = 1_000;
const MAX_DLQ_SCAN_CALLS = 64;
const MAX_DLQ_CURSOR_BYTES = 256 * 1_024;

const keyPart = (value: string): string => encodeURIComponent(value);
const eventKey = (eventId: string): string => `event:${keyPart(eventId)}`;
const eventJobsKey = (eventId: string): string => `event-jobs:${keyPart(eventId)}`;
const jobKey = (jobId: string): string => `job:${keyPart(jobId)}`;
const monthIndexKey = (tenantId: string): string => `evt-months:${keyPart(tenantId)}`;
const retainedEventIndexKey = (tenantId: string): string => `evt-index:${keyPart(tenantId)}`;
const eventStreamKey = (tenantId: string, month: string): string => `evt:${keyPart(tenantId)}:${month}`;
const attemptStreamKey = (tenantId: string, month: string): string => `attempt:${keyPart(tenantId)}:${month}`;
const activeMonthJobsKey = (tenantId: string, month: string): string => `active:${keyPart(tenantId)}:${month}`;
const pausedEndpointKey = (tenantId: string, endpointId: string): string =>
  `paused:${keyPart(tenantId)}:${keyPart(endpointId)}`;
const pausedMonthKey = (tenantId: string, month: string): string => `paused-month:${keyPart(tenantId)}:${month}`;
const archiveStateKey = (tenantId: string, month: string): string => `archive:${keyPart(tenantId)}:${month}`;
const circuitKey = (endpointKey: string): string => `circuit:${keyPart(endpointKey)}`;
const dlqMonthIndexKey = (tenantId: string): string => `dlq-months:${keyPart(tenantId)}`;
const dlqKey = (tenantId: string, month: string): string => `dlq:${keyPart(tenantId)}:${month}`;
const eventDeadLettersKey = (eventId: string): string => `event-dlq:${keyPart(eventId)}`;
const endpointDeadLettersKey = (tenantId: string, endpointId: string): string =>
  `dlq-endpoint:${keyPart(tenantId)}:${keyPart(endpointId)}`;
const deadLetterField = (jobId: string, replayCount: number): string => `${keyPart(jobId)}:${String(replayCount)}`;

interface StoredDeadLetterValue {
  readonly acceptedAtMs: number;
  readonly payload: string;
}

interface RedisDeadLetterCursor {
  readonly month: string;
  readonly scanCursor: string;
  readonly pendingFields: readonly string[];
  readonly monthDone: boolean;
}

const storedDeadLetterValue = (value: string): StoredDeadLetterValue => {
  const separator = value.indexOf('\n');
  const acceptedAtMs = Number(separator < 0 ? '' : value.slice(0, separator));
  if (!Number.isSafeInteger(acceptedAtMs) || acceptedAtMs < 0 || separator < 0) {
    throw new Error('dead-letter hash field is malformed');
  }
  return { acceptedAtMs, payload: value.slice(separator + 1) };
};

const encodeDeadLetterCursor = (cursor: RedisDeadLetterCursor): string => {
  const encoded = Buffer.from(JSON.stringify(cursor)).toString('base64url');
  if (encoded.length > MAX_DLQ_CURSOR_BYTES) {
    throw new Error('dead-letter cursor exceeds its encoded size bound');
  }
  return encoded;
};

const decodeDeadLetterCursor = (cursor: string | undefined): RedisDeadLetterCursor | null | undefined => {
  if (cursor === undefined) {
    return undefined;
  }
  if (cursor.length === 0 || cursor.length > MAX_DLQ_CURSOR_BYTES) {
    return null;
  }
  try {
    const decoded = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8')) as unknown;
    if (decoded === null || typeof decoded !== 'object' || Array.isArray(decoded)) {
      return null;
    }
    const candidate = decoded as Partial<RedisDeadLetterCursor>;
    if (
      typeof candidate.month !== 'string' ||
      !/^\d{4}-(?:0[1-9]|1[0-2])$/.test(candidate.month) ||
      typeof candidate.scanCursor !== 'string' ||
      !/^\d+$/.test(candidate.scanCursor) ||
      !Array.isArray(candidate.pendingFields) ||
      candidate.pendingFields.length > MAX_PAGE_LIMIT ||
      candidate.pendingFields.some(field => typeof field !== 'string' || field.length === 0) ||
      typeof candidate.monthDone !== 'boolean'
    ) {
      return null;
    }
    return {
      month: candidate.month,
      scanCursor: candidate.scanCursor,
      pendingFields: candidate.pendingFields as readonly string[],
      monthDone: candidate.monthDone,
    };
  } catch {
    return null;
  }
};

const validPageLimit = (limit: number | undefined): number | null => {
  const normalized = limit ?? DEFAULT_PAGE_LIMIT;
  return Number.isSafeInteger(normalized) && normalized >= 1 && normalized <= MAX_PAGE_LIMIT ? normalized : null;
};

const redisFailure = (
  operation: string,
  error: unknown,
  code: StorageFailure['code'] = 'unavailable',
): StorageFailure => ({
  code,
  operation,
  message: error instanceof Error ? error.message : String(error),
});

const missingJob = (operation: string): StorageFailure => ({
  code: 'invalid-data',
  operation,
  message: 'delivery job not found',
});

const invalidClaimRequest = (
  request: Omit<DeliveryClaimRequest, 'limit'> & { readonly limit?: number },
): StorageFailure | null =>
  request.claimToken.length === 0 ||
  !Number.isSafeInteger(request.nowMs) ||
  request.nowMs < 0 ||
  !Number.isSafeInteger(request.leaseMs) ||
  request.leaseMs < 1 ||
  (request.limit !== undefined && (!Number.isSafeInteger(request.limit) || request.limit < 1 || request.limit > 1_000))
    ? redisFailure('claim-delivery', 'invalid delivery claim request', 'invalid-data')
    : null;

const claimConflict = (operation: string): StorageFailure =>
  redisFailure(operation, 'delivery claim is missing, expired, or owned by another worker', 'conflict');

const closedCircuit = (endpointKey: string): EndpointCircuit => ({
  endpointKey,
  status: 'closed',
});

const streamField = (entry: readonly string[], name: string): string | null => {
  for (let index = 0; index < entry.length - 1; index += 2) {
    if (entry[index] === name) {
      return entry[index + 1] ?? null;
    }
  }
  return null;
};

const loadJob = async (redis: Redis, id: string): Promise<DeliveryJob | null> => {
  const value = await redis.get(jobKey(id));
  return value === null ? null : decodeJob(value);
};

const loadEventMonthForJob = async (redis: Redis, job: DeliveryJob): Promise<string> => {
  const value = await redis.get(eventKey(job.eventId));
  if (value === null) {
    throw new Error(`delivery job ${job.id} is missing its retained event`);
  }
  return eventMonth(decodeEnvelope(value).receivedAtMs);
};

const atomicAcceptScript = `
local existing = redis.call('GET', KEYS[1])
if existing then return {0, existing} end
local function assert_type(key, expected)
  local actual = redis.call('TYPE', key).ok
  return actual == 'none' or actual == expected
end
if redis.call('EXISTS', KEYS[2]) == 1 then
  return redis.error_reply('event id already exists')
end
if not assert_type(KEYS[3], 'set') or
   not assert_type(KEYS[4], 'stream') or
   not assert_type(KEYS[5], 'set') or
   not assert_type(KEYS[6], 'zset') or
   not assert_type(KEYS[7], 'hash') or
   not assert_type(KEYS[8], 'set') then
  return redis.error_reply('acceptance index has an incompatible Redis type')
end
local archive_phase = redis.call('HGET', KEYS[7], 'phase')
if archive_phase == 'deleting' then
  return redis.error_reply('event month is sealed for archive deletion')
end
if archive_phase == 'exporting' then
  local lease_until = tonumber(redis.call('HGET', KEYS[7], 'leaseUntilMs') or '0')
  if lease_until > tonumber(ARGV[6]) then
    return redis.error_reply('event month is leased for archive export')
  end
  redis.call('HSET', KEYS[7], 'phase', 'live')
  redis.call('HDEL', KEYS[7], 'leaseToken', 'leaseUntilMs', 'snapshotCursor', 'manifest')
end
local count = tonumber(ARGV[5])
for i = 1, count do
  if redis.call('EXISTS', KEYS[8 + i]) == 1 then
    return redis.error_reply('delivery job id already exists')
  end
end
redis.call('SET', KEYS[2], ARGV[2])
redis.call('SADD', KEYS[5], ARGV[4])
redis.call('ZADD', KEYS[6], ARGV[6], ARGV[3])
redis.call('XADD', KEYS[4], '*', 'id', ARGV[3], 'envelope', ARGV[2])
for i = 1, count do
  local base = 7 + ((i - 1) * 2)
  local id = ARGV[base]
  local job = ARGV[base + 1]
  redis.call('SET', KEYS[8 + i], job)
  redis.call('SADD', KEYS[3], id)
  redis.call('SADD', KEYS[8], id)
end
redis.call('HSET', KEYS[7], 'phase', 'live')
redis.call('HINCRBY', KEYS[7], 'version', 1)
local claimed = redis.call('SET', KEYS[1], ARGV[3], 'NX', 'EX', ARGV[1])
if not claimed then return redis.error_reply('dedup claim changed during atomic acceptance') end
return {1, ARGV[3]}
`;

const acknowledgeEventScript = `
local function assert_type(key, expected)
  local actual = redis.call('TYPE', key).ok
  return actual == 'none' or actual == expected
end
if not assert_type(KEYS[2], 'set') or not assert_type(KEYS[3], 'zset') then
  return redis.error_reply('acknowledgement index has an incompatible Redis type')
end
local encoded = redis.call('GET', KEYS[1])
if not encoded then return 0 end
local event = cjson.decode(encoded)
if event.acknowledgedAtMs ~= nil then return 1 end
local jobs = redis.call('SMEMBERS', KEYS[2])
for _, id in ipairs(jobs) do
  redis.call('ZADD', KEYS[3], ARGV[1], id)
end
event.acknowledgedAtMs = tonumber(ARGV[1])
redis.call('SET', KEYS[1], cjson.encode(event))
return 1
`;

const claimDueJobsScript = `
local expired = redis.call('ZRANGEBYSCORE', KEYS[3], '-inf', ARGV[1])
for _, id in ipairs(expired) do
  redis.call('HDEL', KEYS[2], id)
  redis.call('ZREM', KEYS[3], id)
end
local scan_limit = math.max(tonumber(ARGV[2]), math.min(1000, tonumber(ARGV[2]) * 4))
local due = redis.call('ZRANGEBYSCORE', KEYS[1], '-inf', ARGV[1], 'LIMIT', 0, scan_limit)
local claimed = {}
for _, id in ipairs(due) do
  if #claimed >= tonumber(ARGV[2]) then break end
  if redis.call('HEXISTS', KEYS[2], id) == 0 then
    redis.call('HSET', KEYS[2], id, ARGV[4])
    redis.call('ZADD', KEYS[3], ARGV[3], id)
    table.insert(claimed, id)
  end
end
return claimed
`;

const claimJobScript = `
local expiry = tonumber(redis.call('ZSCORE', KEYS[2], ARGV[1]) or '-1')
if expiry >= 0 and expiry <= tonumber(ARGV[2]) then
  redis.call('HDEL', KEYS[1], ARGV[1])
  redis.call('ZREM', KEYS[2], ARGV[1])
end
if redis.call('HEXISTS', KEYS[1], ARGV[1]) == 1 then return 0 end
redis.call('HSET', KEYS[1], ARGV[1], ARGV[4])
redis.call('ZADD', KEYS[2], ARGV[3], ARGV[1])
return 1
`;

const releaseClaimScript = `
local owner = redis.call('HGET', KEYS[1], ARGV[1])
local expiry = tonumber(redis.call('ZSCORE', KEYS[2], ARGV[1]) or '-1')
if expiry >= 0 and expiry <= tonumber(ARGV[3]) then
  redis.call('HDEL', KEYS[1], ARGV[1])
  redis.call('ZREM', KEYS[2], ARGV[1])
  return 0
end
if not owner or owner ~= ARGV[2] then return 0 end
redis.call('HDEL', KEYS[1], ARGV[1])
redis.call('ZREM', KEYS[2], ARGV[1])
return 1
`;

const recordAttemptScript = `
local owner = redis.call('HGET', KEYS[2], ARGV[1])
local expiry = tonumber(redis.call('ZSCORE', KEYS[3], ARGV[1]) or '-1')
if expiry >= 0 and expiry <= tonumber(ARGV[4]) then
  redis.call('HDEL', KEYS[2], ARGV[1])
  redis.call('ZREM', KEYS[3], ARGV[1])
  owner = false
end
if (owner and (ARGV[2] == '' or owner ~= ARGV[2])) or (not owner and ARGV[2] ~= '') then return 0 end
local stream_type = redis.call('TYPE', KEYS[4]).ok
if stream_type ~= 'none' and stream_type ~= 'stream' then
  return redis.error_reply('attempt stream has an incompatible Redis type')
end
redis.call('XADD', KEYS[4], '*', 'job', ARGV[1], 'attempt', ARGV[5])
redis.call('SET', KEYS[1], ARGV[3])
return 1
`;

const transitionJobScript = `
local owner = redis.call('HGET', KEYS[2], ARGV[1])
local expiry = tonumber(redis.call('ZSCORE', KEYS[3], ARGV[1]) or '-1')
if expiry >= 0 and expiry <= tonumber(ARGV[5]) then
  redis.call('HDEL', KEYS[2], ARGV[1])
  redis.call('ZREM', KEYS[3], ARGV[1])
  owner = false
end
if (owner and (ARGV[2] == '' or owner ~= ARGV[2])) or (not owner and ARGV[2] ~= '') then return 0 end
local current = redis.call('GET', KEYS[1])
if not current or current ~= ARGV[3] then return 0 end
local ready_type = redis.call('TYPE', KEYS[4]).ok
local retry_type = redis.call('TYPE', KEYS[5]).ok
local paused_expiry_type = redis.call('TYPE', KEYS[6]).ok
local paused_endpoint_type = redis.call('TYPE', KEYS[7]).ok
local paused_month_type = redis.call('TYPE', KEYS[8]).ok
local active_type = redis.call('TYPE', KEYS[9]).ok
local endpoint_dlq_type = redis.call('TYPE', KEYS[10]).ok
if (ready_type ~= 'none' and ready_type ~= 'zset') or
   (retry_type ~= 'none' and retry_type ~= 'zset') or
   (paused_expiry_type ~= 'none' and paused_expiry_type ~= 'zset') or
   (paused_endpoint_type ~= 'none' and paused_endpoint_type ~= 'set') or
   (paused_month_type ~= 'none' and paused_month_type ~= 'set') or
   (active_type ~= 'none' and active_type ~= 'set') or
   (endpoint_dlq_type ~= 'none' and endpoint_dlq_type ~= 'hash') then
  return redis.error_reply('delivery queue has an incompatible Redis type')
end
if ARGV[6] == 'schedule' then
  redis.call('ZADD', KEYS[4], ARGV[7], ARGV[1])
  redis.call('ZADD', KEYS[5], ARGV[7], ARGV[1])
  redis.call('ZREM', KEYS[6], ARGV[1])
  redis.call('SREM', KEYS[7], ARGV[1])
  redis.call('SREM', KEYS[8], ARGV[1])
elseif ARGV[6] == 'pause' then
  redis.call('ZREM', KEYS[4], ARGV[1])
  redis.call('ZREM', KEYS[5], ARGV[1])
  redis.call('ZADD', KEYS[6], ARGV[7], ARGV[1])
  redis.call('SADD', KEYS[7], ARGV[1])
  redis.call('SADD', KEYS[8], ARGV[1])
else
  redis.call('ZREM', KEYS[4], ARGV[1])
  redis.call('ZREM', KEYS[5], ARGV[1])
  redis.call('ZREM', KEYS[6], ARGV[1])
  redis.call('SREM', KEYS[7], ARGV[1])
  redis.call('SREM', KEYS[8], ARGV[1])
  redis.call('SREM', KEYS[9], ARGV[1])
end
redis.call('HDEL', KEYS[10], ARGV[1])
redis.call('SET', KEYS[1], ARGV[4])
if ARGV[8] ~= '1' then
  redis.call('HDEL', KEYS[2], ARGV[1])
  redis.call('ZREM', KEYS[3], ARGV[1])
end
return 1
`;

const deadLetterScript = `
local owner = redis.call('HGET', KEYS[2], ARGV[1])
local expiry = tonumber(redis.call('ZSCORE', KEYS[3], ARGV[1]) or '-1')
if expiry >= 0 and expiry <= tonumber(ARGV[5]) then
  redis.call('HDEL', KEYS[2], ARGV[1])
  redis.call('ZREM', KEYS[3], ARGV[1])
  owner = false
end
if (owner and (ARGV[2] == '' or owner ~= ARGV[2])) or (not owner and ARGV[2] ~= '') then return 0 end
local current = redis.call('GET', KEYS[1])
if not current or current ~= ARGV[3] then return 0 end
local dlq_type = redis.call('TYPE', KEYS[6]).ok
local ready_type = redis.call('TYPE', KEYS[4]).ok
local retry_type = redis.call('TYPE', KEYS[5]).ok
local event_dlq_type = redis.call('TYPE', KEYS[7]).ok
local month_index_type = redis.call('TYPE', KEYS[8]).ok
local paused_expiry_type = redis.call('TYPE', KEYS[9]).ok
local paused_endpoint_type = redis.call('TYPE', KEYS[10]).ok
local paused_month_type = redis.call('TYPE', KEYS[11]).ok
local active_type = redis.call('TYPE', KEYS[12]).ok
local endpoint_dlq_type = redis.call('TYPE', KEYS[13]).ok
if (dlq_type ~= 'none' and dlq_type ~= 'hash') or
   (ready_type ~= 'none' and ready_type ~= 'zset') or
   (retry_type ~= 'none' and retry_type ~= 'zset') or
   (event_dlq_type ~= 'none' and event_dlq_type ~= 'hash') or
   (month_index_type ~= 'none' and month_index_type ~= 'hash') or
   (paused_expiry_type ~= 'none' and paused_expiry_type ~= 'zset') or
   (paused_endpoint_type ~= 'none' and paused_endpoint_type ~= 'set') or
   (paused_month_type ~= 'none' and paused_month_type ~= 'set') or
   (active_type ~= 'none' and active_type ~= 'set') or
   (endpoint_dlq_type ~= 'none' and endpoint_dlq_type ~= 'hash') then
  return redis.error_reply('dead-letter index has an incompatible Redis type')
end
local server_time = redis.call('TIME')
local server_now_ms = (tonumber(server_time[1]) * 1000) + math.floor(tonumber(server_time[2]) / 1000)
local retention_ms = tonumber(ARGV[8])
local expires_at_ms = server_now_ms + retention_ms
local stored_entry = tostring(server_now_ms) .. '\\n' .. ARGV[6]
local stored_job = tostring(server_now_ms) .. '\\n' .. ARGV[4]
redis.call('DEL', KEYS[14])
redis.call('HSET', KEYS[14], 'probe', '1')
redis.call('PEXPIREAT', KEYS[14], expires_at_ms)
local probe_expiry = redis.call('HPEXPIREAT', KEYS[14], expires_at_ms, 'FIELDS', 1, 'probe')
if tonumber(probe_expiry[1]) ~= 1 then
  return redis.error_reply('Redis hash-field expiry semantics are unavailable')
end
redis.call('DEL', KEYS[14])
local function set_expiring_field(key, field, value)
  redis.call('HSET', key, field, value)
  redis.call('HPEXPIREAT', key, expires_at_ms, 'FIELDS', 1, field)
end
set_expiring_field(KEYS[6], ARGV[9], stored_entry)
set_expiring_field(KEYS[7], ARGV[9], stored_entry)
set_expiring_field(KEYS[8], ARGV[7], tostring(server_now_ms))
set_expiring_field(KEYS[13], ARGV[1], stored_job)
redis.call('ZREM', KEYS[4], ARGV[1])
redis.call('ZREM', KEYS[5], ARGV[1])
redis.call('ZREM', KEYS[9], ARGV[1])
redis.call('SREM', KEYS[10], ARGV[1])
redis.call('SREM', KEYS[11], ARGV[1])
redis.call('SREM', KEYS[12], ARGV[1])
redis.call('SET', KEYS[1], ARGV[4])
redis.call('HDEL', KEYS[2], ARGV[1])
redis.call('ZREM', KEYS[3], ARGV[1])
return 1
`;

const quotaScript = `
local now = tonumber(ARGV[1])
local rate = tonumber(ARGV[2])
local burst = tonumber(ARGV[3])
local state = redis.call('HMGET', KEYS[1], 'tokens', 'updated')
local tokens = tonumber(state[1]) or burst
local updated = tonumber(state[2]) or now
local elapsed = math.max(0, now - updated)
tokens = math.min(burst, tokens + ((elapsed * rate) / 1000))
local allowed = 0
local retry = 0
if tokens >= 1 then
  tokens = tokens - 1
  allowed = 1
else
  retry = math.max(1, math.ceil((1 - tokens) / rate))
end
redis.call('HSET', KEYS[1], 'tokens', tostring(tokens), 'updated', tostring(now))
redis.call('PEXPIRE', KEYS[1], math.max(1000, math.ceil((burst / rate) * 2000)))
return {allowed, retry}
`;

const replayJobsScript = `
local phase = redis.call('HGET', KEYS[2], 'phase')
if phase == 'deleting' then return -2 end
if phase == 'exporting' then
  local lease_until = tonumber(redis.call('HGET', KEYS[2], 'leaseUntilMs') or '0')
  if lease_until > tonumber(ARGV[1]) then return -2 end
  redis.call('HSET', KEYS[2], 'phase', 'live')
  redis.call('HDEL', KEYS[2], 'leaseToken', 'leaseUntilMs', 'snapshotCursor', 'manifest')
end
if redis.call('EXISTS', KEYS[1]) == 0 then return -1 end
local ready_type = redis.call('TYPE', KEYS[3]).ok
local retry_type = redis.call('TYPE', KEYS[4]).ok
local claims_type = redis.call('TYPE', KEYS[5]).ok
local claim_expiries_type = redis.call('TYPE', KEYS[6]).ok
local paused_expiries_type = redis.call('TYPE', KEYS[7]).ok
local active_type = redis.call('TYPE', KEYS[8]).ok
if (ready_type ~= 'none' and ready_type ~= 'zset') or
   (retry_type ~= 'none' and retry_type ~= 'zset') or
   (claims_type ~= 'none' and claims_type ~= 'hash') or
   (claim_expiries_type ~= 'none' and claim_expiries_type ~= 'zset') or
   (paused_expiries_type ~= 'none' and paused_expiries_type ~= 'zset') or
   (active_type ~= 'none' and active_type ~= 'set') then
  return redis.error_reply('replay index has an incompatible Redis type')
end
local count = tonumber(ARGV[3])
for i = 1, count do
  local key_base = 8 + ((i - 1) * 4)
  local argument_base = 3 + ((i - 1) * 3)
  local current = redis.call('GET', KEYS[key_base + 1])
  if not current or current ~= ARGV[argument_base + 1] then return 0 end
  local endpoint_type = redis.call('TYPE', KEYS[key_base + 2]).ok
  local month_type = redis.call('TYPE', KEYS[key_base + 3]).ok
  local endpoint_dlq_type = redis.call('TYPE', KEYS[key_base + 4]).ok
  if (endpoint_type ~= 'none' and endpoint_type ~= 'set') or
     (month_type ~= 'none' and month_type ~= 'set') or
     (endpoint_dlq_type ~= 'none' and endpoint_dlq_type ~= 'hash') then
    return redis.error_reply('paused index has an incompatible Redis type')
  end
  local id = ARGV[argument_base + 3]
  local claim_expiry = tonumber(redis.call('ZSCORE', KEYS[6], id) or '-1')
  if claim_expiry >= 0 and claim_expiry <= tonumber(ARGV[1]) then
    redis.call('HDEL', KEYS[5], id)
    redis.call('ZREM', KEYS[6], id)
  end
  if redis.call('HEXISTS', KEYS[5], id) == 1 then return -3 end
end
for i = 1, count do
  local key_base = 8 + ((i - 1) * 4)
  local argument_base = 3 + ((i - 1) * 3)
  local id = ARGV[argument_base + 3]
  redis.call('SET', KEYS[key_base + 1], ARGV[argument_base + 2])
  redis.call('ZADD', KEYS[3], ARGV[1], id)
  redis.call('ZREM', KEYS[4], id)
  redis.call('ZREM', KEYS[7], id)
  redis.call('SREM', KEYS[key_base + 2], id)
  redis.call('SREM', KEYS[key_base + 3], id)
  redis.call('HDEL', KEYS[key_base + 4], id)
  redis.call('SADD', KEYS[8], id)
  redis.call('HDEL', KEYS[5], id)
  redis.call('ZREM', KEYS[6], id)
end
redis.call('HSET', KEYS[2], 'phase', 'live')
redis.call('HINCRBY', KEYS[2], 'version', 1)
return 1
`;

const cleanEndpointDeadLetterIndexScript = `
local index_type = redis.call('TYPE', KEYS[1]).ok
if index_type ~= 'none' and index_type ~= 'hash' then
  return redis.error_reply('endpoint dead-letter index has an incompatible Redis type')
end
local removed = 0
local count = tonumber(ARGV[1])
for i = 1, count do
  local argument_base = 1 + ((i - 1) * 3)
  local id = ARGV[argument_base + 1]
  local observed_index = ARGV[argument_base + 2]
  local observed_job = ARGV[argument_base + 3]
  local current_index = redis.call('HGET', KEYS[1], id)
  local current_job = redis.call('GET', KEYS[1 + i])
  if current_index == observed_index and
     ((not current_job and observed_job == '') or current_job == observed_job) then
    removed = removed + redis.call('HDEL', KEYS[1], id)
  end
end
return removed
`;

const beginArchiveScript = `
local function assert_type(key, expected)
  local actual = redis.call('TYPE', key).ok
  return actual == 'none' or actual == expected
end
if not assert_type(KEYS[1], 'hash') or
   not assert_type(KEYS[2], 'stream') or
   not assert_type(KEYS[3], 'set') then
  return redis.error_reply('archive index has an incompatible Redis type')
end
if redis.call('XLEN', KEYS[2]) == 0 then return {-3} end
if redis.call('SCARD', KEYS[3]) > 0 then return {-2} end
local phase = redis.call('HGET', KEYS[1], 'phase') or 'live'
local owner = redis.call('HGET', KEYS[1], 'leaseToken') or ''
local lease_until = tonumber(redis.call('HGET', KEYS[1], 'leaseUntilMs') or '0')
if phase ~= 'live' and owner ~= ARGV[1] and lease_until > tonumber(ARGV[2]) then return {0} end
local version = tonumber(redis.call('HGET', KEYS[1], 'version') or '0')
local next_phase = phase == 'deleting' and 'deleting' or 'exporting'
local snapshot = redis.call('HGET', KEYS[1], 'snapshotCursor')
if not snapshot or phase == 'live' then
  local last = redis.call('XREVRANGE', KEYS[2], '+', '-', 'COUNT', 1)
  snapshot = last[1][1]
end
local manifest = redis.call('HGET', KEYS[1], 'manifest') or ''
local next_until = tonumber(ARGV[2]) + tonumber(ARGV[3])
redis.call('HSET', KEYS[1],
  'phase', next_phase,
  'version', version,
  'leaseToken', ARGV[1],
  'leaseUntilMs', next_until,
  'snapshotCursor', snapshot)
return {1, tostring(version), next_phase, tostring(next_until), snapshot, manifest}
`;

const renewArchiveScript = `
local phase = redis.call('HGET', KEYS[1], 'phase')
local version = tonumber(redis.call('HGET', KEYS[1], 'version') or '-1')
local owner = redis.call('HGET', KEYS[1], 'leaseToken')
local lease_until = tonumber(redis.call('HGET', KEYS[1], 'leaseUntilMs') or '-1')
if phase ~= ARGV[1] or version ~= tonumber(ARGV[2]) or owner ~= ARGV[3] or lease_until < tonumber(ARGV[4]) then
  return 0
end
local next_until = tonumber(ARGV[4]) + tonumber(ARGV[5])
redis.call('HSET', KEYS[1], 'leaseUntilMs', next_until)
return next_until
`;

const assertArchiveLeaseScript = `
local phase = redis.call('HGET', KEYS[1], 'phase')
local version = tonumber(redis.call('HGET', KEYS[1], 'version') or '-1')
local owner = redis.call('HGET', KEYS[1], 'leaseToken')
local lease_until = tonumber(redis.call('HGET', KEYS[1], 'leaseUntilMs') or '-1')
if phase ~= ARGV[1] or version ~= tonumber(ARGV[2]) or owner ~= ARGV[3] or lease_until < tonumber(ARGV[4]) then
  return 0
end
return 1
`;

const sealArchiveScript = `
local valid = redis.call('HGET', KEYS[1], 'phase') == 'exporting' and
  tonumber(redis.call('HGET', KEYS[1], 'version') or '-1') == tonumber(ARGV[1]) and
  redis.call('HGET', KEYS[1], 'leaseToken') == ARGV[2] and
  tonumber(redis.call('HGET', KEYS[1], 'leaseUntilMs') or '-1') >= tonumber(ARGV[3])
if not valid then return 0 end
redis.call('HSET', KEYS[1], 'phase', 'deleting', 'manifest', ARGV[4])
return 1
`;

const deleteArchivePageScript = `
local valid = redis.call('HGET', KEYS[1], 'phase') == 'deleting' and
  tonumber(redis.call('HGET', KEYS[1], 'version') or '-1') == tonumber(ARGV[1]) and
  redis.call('HGET', KEYS[1], 'leaseToken') == ARGV[2] and
  tonumber(redis.call('HGET', KEYS[1], 'leaseUntilMs') or '-1') >= tonumber(ARGV[3])
if not valid then return {-1, 0} end
local count = tonumber(ARGV[6])
for i = 1, count do
  local key_base = 12 + ((i - 1) * 2)
  local endpoint_dlq_type = redis.call('TYPE', KEYS[key_base + 2]).ok
  if endpoint_dlq_type ~= 'none' and endpoint_dlq_type ~= 'hash' then
    return redis.error_reply('archive endpoint dead-letter index has an incompatible Redis type')
  end
end
for i = 1, count do
  local key_base = 12 + ((i - 1) * 2)
  local id = ARGV[6 + i]
  redis.call('SREM', KEYS[4], id)
  redis.call('DEL', KEYS[key_base + 1])
  redis.call('HDEL', KEYS[key_base + 2], id)
  redis.call('ZREM', KEYS[5], id)
  redis.call('ZREM', KEYS[6], id)
  redis.call('HDEL', KEYS[7], id)
  redis.call('ZREM', KEYS[8], id)
  redis.call('ZREM', KEYS[9], id)
  redis.call('SREM', KEYS[10], id)
end
local deleted_event = 0
if redis.call('SCARD', KEYS[4]) == 0 then
  redis.call('DEL', KEYS[2], KEYS[4], KEYS[11])
  redis.call('XDEL', KEYS[3], ARGV[4])
  redis.call('ZREM', KEYS[12], ARGV[5])
  deleted_event = 1
end
return {1, deleted_event}
`;

const completeArchiveScript = `
local valid = redis.call('HGET', KEYS[1], 'phase') == 'deleting' and
  tonumber(redis.call('HGET', KEYS[1], 'version') or '-1') == tonumber(ARGV[1]) and
  redis.call('HGET', KEYS[1], 'leaseToken') == ARGV[2]
if not valid or redis.call('XLEN', KEYS[2]) ~= 0 then return 0 end
redis.call('DEL', KEYS[1], KEYS[2], KEYS[3], KEYS[4], KEYS[5], KEYS[6])
redis.call('SREM', KEYS[7], ARGV[3])
redis.call('HDEL', KEYS[8], ARGV[3])
return 1
`;

const abortArchiveScript = `
local valid = redis.call('HGET', KEYS[1], 'phase') == 'exporting' and
  tonumber(redis.call('HGET', KEYS[1], 'version') or '-1') == tonumber(ARGV[1]) and
  redis.call('HGET', KEYS[1], 'leaseToken') == ARGV[2]
if not valid then return 0 end
redis.call('HSET', KEYS[1], 'phase', 'live')
redis.call('HDEL', KEYS[1], 'leaseToken', 'leaseUntilMs', 'snapshotCursor', 'manifest')
return 1
`;

/** ioredis implementation matching Upstash's Redis command semantics. */
export class RedisFlowStore implements FlowStore {
  readonly dlqRetentionMs: number;

  constructor(
    readonly landscape: string,
    readonly redis: Redis,
    options: Readonly<{ dlqRetentionMs?: number }> = {},
  ) {
    const retentionMs = options.dlqRetentionMs ?? MAX_DLQ_RETENTION_MS;
    if (!Number.isSafeInteger(retentionMs) || retentionMs < 1 || retentionMs > MAX_DLQ_RETENTION_MS) {
      throw new RangeError('DLQ retention must be a positive duration no greater than 72 hours');
    }
    this.dlqRetentionMs = retentionMs;
  }

  async consumeQuota(request: QuotaRequest): Promise<Result<QuotaDecision, StorageFailure>> {
    if (request.ratePerSecond <= 0 || request.burst <= 0) {
      return Err(redisFailure('consume-quota', 'quota rate and burst must be positive', 'invalid-data'));
    }
    try {
      const raw = (await this.redis.eval(
        quotaScript,
        1,
        `quota:${keyPart(request.tenantId)}:bucket`,
        String(request.nowMs),
        String(request.ratePerSecond),
        String(request.burst),
      )) as [number | string, number | string];
      return Ok({
        allowed: Number(raw[0]) === 1,
        retryAfterSeconds: Number(raw[1]),
      });
    } catch (error) {
      return Err(redisFailure('consume-quota', error));
    }
  }

  async acceptOnce(request: AtomicAcceptRequest): Promise<Result<AtomicAcceptOutcome, StorageFailure>> {
    const jobIds = request.jobs.map(job => job.id);
    const obligationIds = request.envelope.obligations.map(obligation => obligation.id);
    if (
      !Number.isSafeInteger(request.dedupTtlSeconds) ||
      request.dedupTtlSeconds < 1 ||
      new Set(jobIds).size !== jobIds.length ||
      jobIds.length !== obligationIds.length ||
      jobIds.some(id => !obligationIds.includes(id))
    ) {
      return Err(
        redisFailure(
          'accept-once',
          'dedup TTL must be positive and jobs must match endpoint obligations one-for-one',
          'invalid-data',
        ),
      );
    }

    try {
      const month = eventMonth(request.envelope.receivedAtMs);
      const keys = [
        request.dedupKey,
        eventKey(request.envelope.id),
        eventJobsKey(request.envelope.id),
        eventStreamKey(request.envelope.tenantId, month),
        monthIndexKey(request.envelope.tenantId),
        retainedEventIndexKey(request.envelope.tenantId),
        archiveStateKey(request.envelope.tenantId, month),
        activeMonthJobsKey(request.envelope.tenantId, month),
        ...request.jobs.map(job => jobKey(job.id)),
      ];
      const argumentsList = [
        String(request.dedupTtlSeconds),
        encodeEnvelope(request.envelope),
        request.envelope.id,
        month,
        String(request.jobs.length),
        String(request.envelope.receivedAtMs),
        ...request.jobs.flatMap(job => [job.id, encodeJob(job)]),
      ];
      const raw = (await this.redis.eval(atomicAcceptScript, keys.length, ...keys, ...argumentsList)) as [
        number | string,
        string,
      ];
      const eventId = String(raw[1]);
      return Ok(Number(raw[0]) === 0 ? { kind: 'duplicate', eventId } : { kind: 'accepted', eventId });
    } catch (error) {
      return Err(redisFailure('accept-once', error));
    }
  }

  async acknowledgeEvent(eventId: string, acknowledgedAtMs: number): Promise<Result<void, StorageFailure>> {
    if (!Number.isSafeInteger(acknowledgedAtMs) || acknowledgedAtMs < 0) {
      return Err(redisFailure('acknowledge-event', 'acknowledgement timestamp is invalid', 'invalid-data'));
    }
    try {
      const acknowledged = Number(
        await this.redis.eval(
          acknowledgeEventScript,
          3,
          eventKey(eventId),
          eventJobsKey(eventId),
          READY_QUEUE_KEY,
          String(acknowledgedAtMs),
        ),
      );
      return acknowledged === 1
        ? Ok(undefined)
        : Err(redisFailure('acknowledge-event', 'accepted event not found', 'invalid-data'));
    } catch (error) {
      return Err(redisFailure('acknowledge-event', error));
    }
  }

  async getEvent(eventId: string): Promise<Result<WebhookEnvelope | null, StorageFailure>> {
    try {
      const value = await this.redis.get(eventKey(eventId));
      return Ok(value === null ? null : decodeEnvelope(value));
    } catch (error) {
      return Err(redisFailure('get-event', error));
    }
  }

  async getJob(id: string): Promise<Result<DeliveryJob | null, StorageFailure>> {
    try {
      return Ok(await loadJob(this.redis, id));
    } catch (error) {
      return Err(redisFailure('get-job', error));
    }
  }

  async listEventJobs(eventId: string): Promise<Result<readonly DeliveryJob[], StorageFailure>> {
    try {
      const ids = await this.redis.smembers(eventJobsKey(eventId));
      if (ids.length === 0) {
        return Ok([]);
      }
      const values = await this.redis.mget(ids.map(jobKey));
      return Ok(values.filter((value): value is string => value !== null).map(decodeJob));
    } catch (error) {
      return Err(redisFailure('list-event-jobs', error));
    }
  }

  async listRetainedEvents(query: RetainedEventQuery): Promise<Result<RetainedEventPage, StorageFailure>> {
    const offset = retainedEventOffset(query.cursor);
    const limit = retainedEventLimit(query.limit);
    if (offset === null || limit === null) {
      return Err(redisFailure('list-retained-events', 'invalid retained-event cursor or limit', 'invalid-data'));
    }

    try {
      const items: RetainedEventPage['items'][number][] = [];
      const batchSize = Math.max(50, Math.min(400, limit * 2));
      const maximum = query.receivedBeforeMs ?? '+inf';
      const minimum = query.receivedAfterMs ?? '-inf';
      let scanOffset = offset;
      let exhausted = false;

      while (items.length < limit && !exhausted) {
        const ids = await this.redis.zrevrangebyscore(
          retainedEventIndexKey(query.tenantId),
          maximum,
          minimum,
          'LIMIT',
          scanOffset,
          batchSize,
        );
        if (ids.length === 0) {
          exhausted = true;
          break;
        }
        const values = await this.redis.mget(ids.map(eventKey));
        let processed = 0;
        for (const value of values) {
          processed += 1;
          if (value === null) {
            continue;
          }
          const envelope = decodeEnvelope(value);
          const jobsResult = await this.listEventJobs(envelope.id);
          if (await jobsResult.isErr()) {
            return Err(await jobsResult.unwrapErr());
          }
          const record = retainedEventRecord(envelope, await jobsResult.unwrap());
          if (retainedEventMatches(record, query)) {
            items.push(record);
            if (items.length === limit) {
              break;
            }
          }
        }
        scanOffset += processed;
        exhausted = processed === ids.length && ids.length < batchSize;
      }

      return Ok({
        items,
        ...(!exhausted ? { nextCursor: String(scanOffset) } : {}),
      });
    } catch (error) {
      return Err(redisFailure('list-retained-events', error));
    }
  }

  async claimDueJobs(request: DeliveryClaimRequest): Promise<Result<readonly DeliveryJobClaim[], StorageFailure>> {
    const invalid = invalidClaimRequest(request);
    if (invalid !== null) {
      return Err(invalid);
    }
    const limit = request.limit ?? 100;
    const leasedUntilMs = request.nowMs + request.leaseMs;
    try {
      const ids = (await this.redis.eval(
        claimDueJobsScript,
        3,
        READY_QUEUE_KEY,
        DELIVERY_CLAIMS_KEY,
        DELIVERY_CLAIM_EXPIRIES_KEY,
        String(request.nowMs),
        String(limit),
        String(leasedUntilMs),
        request.claimToken,
      )) as string[];
      if (ids.length === 0) {
        return Ok([]);
      }
      const values = await this.redis.mget(ids.map(jobKey));
      const claims: DeliveryJobClaim[] = [];
      for (let index = 0; index < ids.length; index += 1) {
        const id = ids[index];
        const value = values[index];
        if (id === undefined) {
          continue;
        }
        if (value === null || value === undefined) {
          await this.releaseJobClaim(id, request.claimToken);
          await this.redis.zrem(READY_QUEUE_KEY, id);
          continue;
        }
        const job = decodeJob(value);
        if (job.status !== 'pending') {
          await this.releaseJobClaim(id, request.claimToken);
          await this.redis.zrem(READY_QUEUE_KEY, id);
          continue;
        }
        claims.push({
          claimToken: request.claimToken,
          job,
          leasedUntilMs,
        });
      }
      return Ok(claims);
    } catch (error) {
      return Err(redisFailure('claim-due-jobs', error));
    }
  }

  async claimJob(
    jobId: string,
    request: Omit<DeliveryClaimRequest, 'limit'>,
  ): Promise<Result<DeliveryJobClaim | null, StorageFailure>> {
    const invalid = invalidClaimRequest(request);
    if (invalid !== null) {
      return Err(invalid);
    }
    try {
      const job = await loadJob(this.redis, jobId);
      if (job === null || job.status === 'completed' || job.status === 'dead-letter') {
        return Ok(null);
      }
      const eventValue = await this.redis.get(eventKey(job.eventId));
      if (eventValue === null || decodeEnvelope(eventValue).acknowledgedAtMs === undefined) {
        return Ok(null);
      }
      const leasedUntilMs = request.nowMs + request.leaseMs;
      const claimed = Number(
        await this.redis.eval(
          claimJobScript,
          2,
          DELIVERY_CLAIMS_KEY,
          DELIVERY_CLAIM_EXPIRIES_KEY,
          jobId,
          String(request.nowMs),
          String(leasedUntilMs),
          request.claimToken,
        ),
      );
      return claimed === 0 ? Ok(null) : Ok({ claimToken: request.claimToken, job, leasedUntilMs });
    } catch (error) {
      return Err(redisFailure('claim-job', error));
    }
  }

  async releaseJobClaim(jobId: string, claimToken: string): Promise<Result<void, StorageFailure>> {
    try {
      const released = Number(
        await this.redis.eval(
          releaseClaimScript,
          2,
          DELIVERY_CLAIMS_KEY,
          DELIVERY_CLAIM_EXPIRIES_KEY,
          jobId,
          claimToken,
          String(Date.now()),
        ),
      );
      return released === 1 ? Ok(undefined) : Err(claimConflict('release-job-claim'));
    } catch (error) {
      return Err(redisFailure('release-job-claim', error));
    }
  }

  async recordAttempt(
    id: string,
    attempt: DeliveryAttempt,
    claimToken?: string,
  ): Promise<Result<DeliveryJob, StorageFailure>> {
    try {
      const current = await loadJob(this.redis, id);
      if (current === null) {
        return Err(missingJob('record-attempt'));
      }
      const updated: DeliveryJob = {
        ...current,
        attempts: [...current.attempts, attempt],
      };
      const transitioned = Number(
        await this.redis.eval(
          recordAttemptScript,
          4,
          jobKey(id),
          DELIVERY_CLAIMS_KEY,
          DELIVERY_CLAIM_EXPIRIES_KEY,
          attemptStreamKey(current.tenantId, eventMonth(attempt.attemptedAtMs)),
          id,
          claimToken ?? '',
          encodeJob(updated),
          String(Date.now()),
          JSON.stringify(attempt),
        ),
      );
      return transitioned === 1 ? Ok(updated) : Err(claimConflict('record-attempt'));
    } catch (error) {
      return Err(redisFailure('record-attempt', error));
    }
  }

  async completeJob(id: string, claimToken?: string): Promise<Result<DeliveryJob, StorageFailure>> {
    try {
      const current = await loadJob(this.redis, id);
      if (current === null) {
        return Err(missingJob('complete-job'));
      }
      const updated: DeliveryJob = { ...current, status: 'completed' };
      const month = await loadEventMonthForJob(this.redis, current);
      const transitioned = Number(
        await this.redis.eval(
          transitionJobScript,
          10,
          jobKey(id),
          DELIVERY_CLAIMS_KEY,
          DELIVERY_CLAIM_EXPIRIES_KEY,
          READY_QUEUE_KEY,
          RETRY_QUEUE_KEY,
          PAUSED_EXPIRIES_KEY,
          pausedEndpointKey(current.tenantId, current.endpointId),
          pausedMonthKey(current.tenantId, month),
          activeMonthJobsKey(current.tenantId, month),
          endpointDeadLettersKey(current.tenantId, current.endpointId),
          id,
          claimToken ?? '',
          encodeJob(current),
          encodeJob(updated),
          String(Date.now()),
          'complete',
          '0',
          '0',
        ),
      );
      return transitioned === 1 ? Ok(updated) : Err(claimConflict('complete-job'));
    } catch (error) {
      return Err(redisFailure('complete-job', error));
    }
  }

  async scheduleJob(
    id: string,
    dueAtMs: number,
    address?: string,
    misrouteRefreshes?: number,
    claimToken?: string,
    retainClaim = false,
  ): Promise<Result<DeliveryJob, StorageFailure>> {
    try {
      const current = await loadJob(this.redis, id);
      if (current === null) {
        return Err(missingJob('schedule-job'));
      }
      const updated: DeliveryJob = {
        ...current,
        dueAtMs,
        status: 'pending',
        ...(address === undefined ? {} : { address }),
        ...(misrouteRefreshes === undefined ? {} : { misrouteRefreshes }),
      };
      const month = await loadEventMonthForJob(this.redis, current);
      const transitioned = Number(
        await this.redis.eval(
          transitionJobScript,
          10,
          jobKey(id),
          DELIVERY_CLAIMS_KEY,
          DELIVERY_CLAIM_EXPIRIES_KEY,
          READY_QUEUE_KEY,
          RETRY_QUEUE_KEY,
          PAUSED_EXPIRIES_KEY,
          pausedEndpointKey(current.tenantId, current.endpointId),
          pausedMonthKey(current.tenantId, month),
          activeMonthJobsKey(current.tenantId, month),
          endpointDeadLettersKey(current.tenantId, current.endpointId),
          id,
          claimToken ?? '',
          encodeJob(current),
          encodeJob(updated),
          String(Date.now()),
          'schedule',
          String(dueAtMs),
          retainClaim ? '1' : '0',
        ),
      );
      return transitioned === 1 ? Ok(updated) : Err(claimConflict('schedule-job'));
    } catch (error) {
      return Err(redisFailure('schedule-job', error));
    }
  }

  async pauseJob(id: string, claimToken?: string): Promise<Result<DeliveryJob, StorageFailure>> {
    try {
      const current = await loadJob(this.redis, id);
      if (current === null) {
        return Err(missingJob('pause-job'));
      }
      const updated: DeliveryJob = { ...current, status: 'paused' };
      const month = await loadEventMonthForJob(this.redis, current);
      const transitioned = Number(
        await this.redis.eval(
          transitionJobScript,
          10,
          jobKey(id),
          DELIVERY_CLAIMS_KEY,
          DELIVERY_CLAIM_EXPIRIES_KEY,
          READY_QUEUE_KEY,
          RETRY_QUEUE_KEY,
          PAUSED_EXPIRIES_KEY,
          pausedEndpointKey(current.tenantId, current.endpointId),
          pausedMonthKey(current.tenantId, month),
          activeMonthJobsKey(current.tenantId, month),
          endpointDeadLettersKey(current.tenantId, current.endpointId),
          id,
          claimToken ?? '',
          encodeJob(current),
          encodeJob(updated),
          String(Date.now()),
          'pause',
          String(current.createdAtMs + current.retryWindowMs),
          '0',
        ),
      );
      return transitioned === 1 ? Ok(updated) : Err(claimConflict('pause-job'));
    } catch (error) {
      return Err(redisFailure('pause-job', error));
    }
  }

  async expirePausedJobs(nowMs: number, limit?: number): Promise<Result<readonly DeadLetterEntry[], StorageFailure>> {
    const boundedLimit = validPageLimit(limit);
    if (!Number.isSafeInteger(nowMs) || nowMs < 0 || boundedLimit === null) {
      return Err(redisFailure('expire-paused-jobs', 'invalid paused-expiry request', 'invalid-data'));
    }
    try {
      const ids = await this.redis.zrangebyscore(PAUSED_EXPIRIES_KEY, '-inf', nowMs, 'LIMIT', 0, boundedLimit);
      if (ids.length === 0) {
        return Ok([]);
      }
      const values = await this.redis.mget(ids.map(jobKey));
      const expired: DeadLetterEntry[] = [];
      const stale: string[] = [];
      for (let index = 0; index < ids.length; index += 1) {
        const id = ids[index];
        const value = values[index];
        if (id === undefined) {
          continue;
        }
        if (value === null || value === undefined) {
          stale.push(id);
          continue;
        }
        const current = decodeJob(value);
        if (current.status !== 'paused') {
          stale.push(id);
          continue;
        }
        const month = await loadEventMonthForJob(this.redis, current);
        const updated: DeliveryJob = { ...current, status: 'dead-letter' };
        const entry: DeadLetterEntry = {
          landscape: this.landscape,
          tenantId: current.tenantId,
          eventId: current.eventId,
          endpointId: current.endpointId,
          jobId: current.id,
          exhaustedAtMs: nowMs,
          reason: 'retry-window-expired',
        };
        const transitioned = Number(
          await this.redis.eval(
            deadLetterScript,
            14,
            jobKey(id),
            DELIVERY_CLAIMS_KEY,
            DELIVERY_CLAIM_EXPIRIES_KEY,
            READY_QUEUE_KEY,
            RETRY_QUEUE_KEY,
            dlqKey(current.tenantId, month),
            eventDeadLettersKey(current.eventId),
            dlqMonthIndexKey(current.tenantId),
            PAUSED_EXPIRIES_KEY,
            pausedEndpointKey(current.tenantId, current.endpointId),
            pausedMonthKey(current.tenantId, month),
            activeMonthJobsKey(current.tenantId, month),
            endpointDeadLettersKey(current.tenantId, current.endpointId),
            DLQ_FIELD_EXPIRY_PROBE_KEY,
            id,
            '',
            encodeJob(current),
            encodeJob(updated),
            String(nowMs),
            JSON.stringify(entry),
            month,
            String(this.dlqRetentionMs),
            deadLetterField(id, current.replayCount),
          ),
        );
        if (transitioned === 1) {
          expired.push(entry);
        }
      }
      if (stale.length > 0) {
        const cleanup = await this.redis
          .multi()
          .zrem(PAUSED_EXPIRIES_KEY, ...stale)
          .exec();
        if (cleanup === null || cleanup.some(([error]) => error !== null)) {
          return Err(redisFailure('expire-paused-jobs', 'Redis paused-index cleanup failed'));
        }
      }
      return Ok(expired);
    } catch (error) {
      return Err(redisFailure('expire-paused-jobs', error));
    }
  }

  async resumeEndpoint(
    tenantId: string,
    endpointId: string,
    nowMs: number,
  ): Promise<Result<readonly DeliveryJob[], StorageFailure>> {
    const indexKey = pausedEndpointKey(tenantId, endpointId);
    try {
      const resumed: DeliveryJob[] = [];
      while (true) {
        const ids = (await this.redis.srandmember(indexKey, DEFAULT_PAGE_LIMIT)) as string[];
        if (ids.length === 0) {
          break;
        }
        const values = await this.redis.mget(ids.map(jobKey));
        const stale: string[] = [];
        const groups = new Map<string, DeliveryJob[]>();
        for (let index = 0; index < ids.length; index += 1) {
          const id = ids[index];
          const value = values[index];
          if (id === undefined) {
            continue;
          }
          if (value === null || value === undefined) {
            stale.push(id);
            continue;
          }
          const current = decodeJob(value);
          if (current.tenantId !== tenantId || current.endpointId !== endpointId || current.status !== 'paused') {
            stale.push(id);
            continue;
          }
          const month = await loadEventMonthForJob(this.redis, current);
          const grouped = groups.get(month) ?? [];
          grouped.push(current);
          groups.set(month, grouped);
        }
        if (stale.length > 0) {
          const cleanup = await this.redis
            .multi()
            .srem(indexKey, ...stale)
            .zrem(PAUSED_EXPIRIES_KEY, ...stale)
            .exec();
          if (cleanup === null || cleanup.some(([error]) => error !== null)) {
            return Err(redisFailure('resume-endpoint', 'Redis paused-index cleanup failed'));
          }
        }
        for (const group of groups.values()) {
          const transitioned = await this.replayJobsAtomically('resume-endpoint', group, nowMs);
          if (await transitioned.isErr()) {
            return Err(await transitioned.unwrapErr());
          }
          resumed.push(...(await transitioned.unwrap()));
        }
      }
      return Ok(resumed);
    } catch (error) {
      return Err(redisFailure('resume-endpoint', error));
    }
  }

  async deadLetter(
    id: string,
    exhaustedAtMs: number,
    reason: string,
    claimToken?: string,
  ): Promise<Result<DeadLetterEntry, StorageFailure>> {
    if (!Number.isSafeInteger(exhaustedAtMs) || exhaustedAtMs < 0 || reason.trim().length === 0) {
      return Err(redisFailure('dead-letter', 'invalid dead-letter transition', 'invalid-data'));
    }
    try {
      const current = await loadJob(this.redis, id);
      if (current === null) {
        return Err(missingJob('dead-letter'));
      }
      const updated: DeliveryJob = { ...current, status: 'dead-letter' };
      const entry: DeadLetterEntry = {
        landscape: this.landscape,
        tenantId: current.tenantId,
        eventId: current.eventId,
        endpointId: current.endpointId,
        jobId: id,
        exhaustedAtMs,
        reason,
      };
      const month = await loadEventMonthForJob(this.redis, current);
      const transitioned = Number(
        await this.redis.eval(
          deadLetterScript,
          14,
          jobKey(id),
          DELIVERY_CLAIMS_KEY,
          DELIVERY_CLAIM_EXPIRIES_KEY,
          READY_QUEUE_KEY,
          RETRY_QUEUE_KEY,
          dlqKey(current.tenantId, month),
          eventDeadLettersKey(current.eventId),
          dlqMonthIndexKey(current.tenantId),
          PAUSED_EXPIRIES_KEY,
          pausedEndpointKey(current.tenantId, current.endpointId),
          pausedMonthKey(current.tenantId, month),
          activeMonthJobsKey(current.tenantId, month),
          endpointDeadLettersKey(current.tenantId, current.endpointId),
          DLQ_FIELD_EXPIRY_PROBE_KEY,
          id,
          claimToken ?? '',
          encodeJob(current),
          encodeJob(updated),
          String(Date.now()),
          JSON.stringify(entry),
          month,
          String(this.dlqRetentionMs),
          deadLetterField(id, current.replayCount),
        ),
      );
      return transitioned === 1 ? Ok(entry) : Err(claimConflict('dead-letter'));
    } catch (error) {
      return Err(redisFailure('dead-letter', error));
    }
  }

  async listDeadLetters(tenantId: string): Promise<Result<readonly DeadLetterEntry[], StorageFailure>> {
    const page = await this.listDeadLetterPage(tenantId);
    return (await page.isErr()) ? Err(await page.unwrapErr()) : Ok((await page.unwrap()).items);
  }

  private async deadLetterMonths(tenantId: string): Promise<readonly string[]> {
    const months = new Set<string>();
    let cursor = '0';
    let scanCalls = 0;
    let inspected = 0;
    do {
      const scanned = await this.redis.hscan(dlqMonthIndexKey(tenantId), cursor, 'COUNT', 64);
      cursor = scanned[0];
      scanCalls += 1;
      if (scanned[1].length % 2 !== 0) {
        throw new Error('dead-letter month index returned an incomplete hash pair');
      }
      for (let index = 0; index < scanned[1].length; index += 2) {
        const month = scanned[1][index];
        if (month === undefined || !/^\d{4}-(?:0[1-9]|1[0-2])$/.test(month)) {
          throw new Error('dead-letter month index contains an invalid month');
        }
        months.add(month);
        inspected += 1;
        if (inspected > MAX_PAGE_LIMIT) {
          throw new Error('dead-letter month index exceeds the bounded retention window');
        }
      }
    } while (cursor !== '0' && scanCalls < MAX_DLQ_SCAN_CALLS);
    if (cursor !== '0') {
      throw new Error('dead-letter month index scan exceeded its bounded call budget');
    }
    return [...months].sort((left, right) => right.localeCompare(left));
  }

  async listDeadLetterPage(
    tenantId: string,
    cursor?: string,
    limit?: number,
  ): Promise<Result<DeadLetterPage, StorageFailure>> {
    const boundedLimit = validPageLimit(limit);
    const decodedCursor = decodeDeadLetterCursor(cursor);
    if (boundedLimit === null || decodedCursor === null) {
      return Err(redisFailure('list-dead-letters', 'invalid dead-letter cursor or limit', 'invalid-data'));
    }
    try {
      // HSCAN order is deliberately opaque. The cursor preserves every over-fetched field without
      // introducing a secondary index whose members could outlive their field-level retention.
      const items: DeadLetterEntry[] = [];
      const months = await this.deadLetterMonths(tenantId);
      if (months.length === 0) {
        return Ok({ items });
      }
      let monthIndex =
        decodedCursor === undefined
          ? 0
          : months.findIndex(month => month === decodedCursor.month || month < decodedCursor.month);
      if (monthIndex < 0) {
        return Ok({ items });
      }
      let state: RedisDeadLetterCursor =
        decodedCursor !== undefined && months[monthIndex] === decodedCursor.month
          ? decodedCursor
          : {
              month: months[monthIndex] ?? '',
              scanCursor: '0',
              pendingFields: [],
              monthDone: false,
            };
      let inspected = 0;
      let scanCalls = 0;
      const continuation = (
        currentMonthIndex: number,
        scanCursor: string,
        pendingFields: readonly string[],
        monthDone: boolean,
      ): string | undefined => {
        if (pendingFields.length > 0 || !monthDone) {
          return encodeDeadLetterCursor({
            month: months[currentMonthIndex] ?? '',
            scanCursor,
            pendingFields,
            monthDone,
          });
        }
        const nextMonth = months[currentMonthIndex + 1];
        return nextMonth === undefined
          ? undefined
          : encodeDeadLetterCursor({
              month: nextMonth,
              scanCursor: '0',
              pendingFields: [],
              monthDone: false,
            });
      };
      while (monthIndex < months.length && items.length < boundedLimit) {
        const month = months[monthIndex];
        if (month === undefined) {
          break;
        }
        if (state.month !== month) {
          state = { month, scanCursor: '0', pendingFields: [], monthDone: false };
        }
        let scanCursor = state.scanCursor;
        let monthDone = state.monthDone;
        let pendingFields = [...state.pendingFields];
        if (pendingFields.length > 0) {
          const values = await this.redis.hmget(dlqKey(tenantId, month), ...pendingFields);
          const retained = pendingFields
            .map((field, index) => {
              const value = values[index];
              return value === null || value === undefined
                ? undefined
                : { field, stored: storedDeadLetterValue(value) };
            })
            .filter((entry): entry is Readonly<{ field: string; stored: StoredDeadLetterValue }> => entry !== undefined)
            .sort(
              (left, right) =>
                right.stored.acceptedAtMs - left.stored.acceptedAtMs || left.field.localeCompare(right.field),
            );
          const room = boundedLimit - items.length;
          for (const entry of retained.slice(0, room)) {
            items.push(JSON.parse(entry.stored.payload) as DeadLetterEntry);
          }
          pendingFields = retained.slice(room).map(entry => entry.field);
          if (pendingFields.length > 0 || items.length === boundedLimit) {
            const nextCursor = continuation(monthIndex, scanCursor, pendingFields, monthDone);
            return Ok({ items, ...(nextCursor === undefined ? {} : { nextCursor }) });
          }
        }
        while (!monthDone && items.length < boundedLimit) {
          if (inspected >= MAX_PAGE_LIMIT || scanCalls >= MAX_DLQ_SCAN_CALLS) {
            return Ok({
              items,
              nextCursor: encodeDeadLetterCursor({
                month,
                scanCursor,
                pendingFields: [],
                monthDone: false,
              }),
            });
          }
          const scanned = await this.redis.hscan(
            dlqKey(tenantId, month),
            scanCursor,
            'COUNT',
            Math.max(1, boundedLimit - items.length),
          );
          scanCalls += 1;
          if (scanned[1].length % 2 !== 0) {
            throw new Error('dead-letter hash returned an incomplete field/value pair');
          }
          const pairs: Array<Readonly<{ field: string; stored: StoredDeadLetterValue }>> = [];
          for (let index = 0; index < scanned[1].length; index += 2) {
            const field = scanned[1][index];
            const value = scanned[1][index + 1];
            if (field !== undefined && value !== undefined) {
              pairs.push({ field, stored: storedDeadLetterValue(value) });
            }
          }
          if (pairs.length > MAX_PAGE_LIMIT) {
            throw new Error('dead-letter hash scan returned an oversized batch');
          }
          const inspectable = pairs.slice(0, MAX_PAGE_LIMIT - inspected);
          const deferred = pairs.slice(inspectable.length).map(entry => entry.field);
          inspected += inspectable.length;
          scanCursor = scanned[0];
          monthDone = scanCursor === '0';
          inspectable.sort(
            (left, right) =>
              right.stored.acceptedAtMs - left.stored.acceptedAtMs || left.field.localeCompare(right.field),
          );
          const room = boundedLimit - items.length;
          for (const entry of inspectable.slice(0, room)) {
            items.push(JSON.parse(entry.stored.payload) as DeadLetterEntry);
          }
          pendingFields = [...inspectable.slice(room).map(entry => entry.field), ...deferred];
          if (
            pendingFields.length > 0 ||
            items.length === boundedLimit ||
            inspected >= MAX_PAGE_LIMIT ||
            scanCalls >= MAX_DLQ_SCAN_CALLS
          ) {
            const nextCursor = continuation(monthIndex, scanCursor, pendingFields, monthDone);
            return Ok({ items, ...(nextCursor === undefined ? {} : { nextCursor }) });
          }
        }
        monthIndex += 1;
        const nextMonth = months[monthIndex];
        if (nextMonth !== undefined) {
          state = { month: nextMonth, scanCursor: '0', pendingFields: [], monthDone: false };
        }
      }
      return Ok({ items });
    } catch (error) {
      return Err(redisFailure('list-dead-letters', error));
    }
  }

  private async replayJobsAtomically(
    operation: string,
    currentJobs: readonly DeliveryJob[],
    nowMs: number,
  ): Promise<Result<readonly DeliveryJob[], StorageFailure>> {
    if (!Number.isSafeInteger(nowMs) || nowMs < 0) {
      return Err(redisFailure(operation, 'invalid replay timestamp', 'invalid-data'));
    }
    if (currentJobs.length === 0) {
      return Ok([]);
    }
    const first = currentJobs[0];
    if (first === undefined) {
      return Ok([]);
    }
    let jobMonths: readonly string[];
    try {
      jobMonths = await Promise.all(currentJobs.map(job => loadEventMonthForJob(this.redis, job)));
    } catch (error) {
      return Err(redisFailure(operation, error, 'invalid-data'));
    }
    const month = jobMonths[0];
    if (
      month === undefined ||
      currentJobs.some((job, index) => job.tenantId !== first.tenantId || jobMonths[index] !== month)
    ) {
      return Err(redisFailure(operation, 'atomic replay jobs must share one tenant month', 'invalid-data'));
    }
    const replayed = currentJobs.map(job => ({
      ...job,
      createdAtMs: nowMs,
      dueAtMs: nowMs,
      status: 'pending' as const,
      replayCount: job.replayCount + 1,
    }));
    const keys = [
      eventKey(first.eventId),
      archiveStateKey(first.tenantId, month),
      READY_QUEUE_KEY,
      RETRY_QUEUE_KEY,
      DELIVERY_CLAIMS_KEY,
      DELIVERY_CLAIM_EXPIRIES_KEY,
      PAUSED_EXPIRIES_KEY,
      activeMonthJobsKey(first.tenantId, month),
      ...currentJobs.flatMap(job => [
        jobKey(job.id),
        pausedEndpointKey(job.tenantId, job.endpointId),
        pausedMonthKey(job.tenantId, month),
        endpointDeadLettersKey(job.tenantId, job.endpointId),
      ]),
    ];
    const argumentsList = [
      String(nowMs),
      month,
      String(currentJobs.length),
      ...currentJobs.flatMap((job, index) => [encodeJob(job), encodeJob(replayed[index] ?? job), job.id]),
    ];
    try {
      const transitioned = Number(await this.redis.eval(replayJobsScript, keys.length, ...keys, ...argumentsList));
      if (transitioned === 1) {
        return Ok(replayed);
      }
      const message =
        transitioned === -2
          ? 'event month is fenced by archive retention'
          : transitioned === -3
            ? 'delivery job has an active claim'
            : 'delivery job changed concurrently';
      return Err(redisFailure(operation, message, 'conflict'));
    } catch (error) {
      return Err(redisFailure(operation, error));
    }
  }

  async replayEvent(eventId: string, nowMs: number): Promise<Result<readonly DeliveryJob[], StorageFailure>> {
    const jobsResult = await this.listEventJobs(eventId);
    if (await jobsResult.isErr()) {
      return Err(await jobsResult.unwrapErr());
    }
    const jobs = await jobsResult.unwrap();
    if (jobs.length === 0 && (await this.redis.exists(eventKey(eventId))) === 0) {
      return Err(redisFailure('replay-event', 'event not found', 'invalid-data'));
    }
    return this.replayJobsAtomically('replay-event', jobs, nowMs);
  }

  async replayEndpoint(
    eventId: string,
    endpointId: string,
    nowMs: number,
  ): Promise<Result<DeliveryJob, StorageFailure>> {
    const jobsResult = await this.listEventJobs(eventId);
    if (await jobsResult.isErr()) {
      return Err(await jobsResult.unwrapErr());
    }
    const current = (await jobsResult.unwrap()).find(job => job.endpointId === endpointId);
    if (current === undefined) {
      return Err(redisFailure('replay-endpoint', 'event endpoint obligation not found', 'invalid-data'));
    }
    const replayed = await this.replayJobsAtomically('replay-endpoint', [current], nowMs);
    if (await replayed.isErr()) {
      return Err(await replayed.unwrapErr());
    }
    const updated = (await replayed.unwrap())[0];
    return updated === undefined
      ? Err(redisFailure('replay-endpoint', 'event endpoint obligation not found', 'invalid-data'))
      : Ok(updated);
  }

  async replayDeadLettersForEndpoint(
    tenantId: string,
    endpointId: string,
    nowMs: number,
  ): Promise<Result<readonly DeliveryJob[], StorageFailure>> {
    try {
      const indexKey = endpointDeadLettersKey(tenantId, endpointId);
      let inspected = 0;
      let scanCalls = 0;
      let scanCursor = '0';
      const candidates = new Map<string, Readonly<{ acceptedAtMs: number; job: DeliveryJob }>>();
      do {
        const scanned = await this.redis.hscan(
          indexKey,
          scanCursor,
          'COUNT',
          Math.min(DEFAULT_PAGE_LIMIT, MAX_PAGE_LIMIT - inspected),
        );
        scanCalls += 1;
        scanCursor = scanned[0];
        if (scanned[1].length % 2 !== 0) {
          throw new Error('endpoint dead-letter hash returned an incomplete field/value pair');
        }
        const indexed: Array<Readonly<{ id: string; observedIndex: string }>> = [];
        for (let index = 0; index < scanned[1].length && inspected < MAX_PAGE_LIMIT; index += 2) {
          const id = scanned[1][index];
          const observedIndex = scanned[1][index + 1];
          if (id !== undefined && observedIndex !== undefined) {
            indexed.push({ id, observedIndex });
            inspected += 1;
          }
        }
        const values = indexed.length === 0 ? [] : await this.redis.mget(indexed.map(entry => jobKey(entry.id)));
        const stale: Array<Readonly<{ id: string; observedIndex: string; observedJob: string | null }>> = [];
        for (let index = 0; index < indexed.length; index += 1) {
          const entry = indexed[index];
          const value = values[index] ?? null;
          if (entry === undefined) {
            continue;
          }
          if (value === null) {
            stale.push({ ...entry, observedJob: null });
            continue;
          }
          const stored = storedDeadLetterValue(entry.observedIndex);
          const current = decodeJob(value);
          if (
            stored.payload !== value ||
            current.status !== 'dead-letter' ||
            current.tenantId !== tenantId ||
            current.endpointId !== endpointId
          ) {
            stale.push({ ...entry, observedJob: value });
            continue;
          }
          candidates.set(current.id, { acceptedAtMs: stored.acceptedAtMs, job: current });
        }
        if (stale.length > 0) {
          await this.redis.eval(
            cleanEndpointDeadLetterIndexScript,
            stale.length + 1,
            indexKey,
            ...stale.map(entry => jobKey(entry.id)),
            String(stale.length),
            ...stale.flatMap(entry => [entry.id, entry.observedIndex, entry.observedJob ?? '']),
          );
        }
      } while (scanCursor !== '0' && inspected < MAX_PAGE_LIMIT && scanCalls < MAX_DLQ_SCAN_CALLS);
      const selected = [...candidates.values()]
        .sort((left, right) => left.acceptedAtMs - right.acceptedAtMs || left.job.id.localeCompare(right.job.id))
        .slice(0, DEFAULT_PAGE_LIMIT)
        .map(entry => entry.job);
      if (selected.length === 0) {
        return Ok([]);
      }
      const groups = new Map<string, DeliveryJob[]>();
      for (const current of selected) {
        const month = await loadEventMonthForJob(this.redis, current);
        const grouped = groups.get(month) ?? [];
        grouped.push(current);
        groups.set(month, grouped);
      }
      const replayed: DeliveryJob[] = [];
      for (const group of groups.values()) {
        const transitioned = await this.replayJobsAtomically('replay-endpoint-dead-letters', group, nowMs);
        if (await transitioned.isErr()) {
          return Err(await transitioned.unwrapErr());
        }
        replayed.push(...(await transitioned.unwrap()));
      }
      return Ok(replayed);
    } catch (error) {
      return Err(redisFailure('replay-endpoint-dead-letters', error));
    }
  }

  async getCircuit(endpointKey: string): Promise<Result<EndpointCircuit, StorageFailure>> {
    try {
      const value = await this.redis.get(circuitKey(endpointKey));
      return Ok(value === null ? closedCircuit(endpointKey) : (JSON.parse(value) as EndpointCircuit));
    } catch (error) {
      return Err(redisFailure('get-circuit', error));
    }
  }

  async recordEndpointFailure(
    endpointKey: string,
    nowMs: number,
    openAfterMs: number,
  ): Promise<Result<EndpointCircuit, StorageFailure>> {
    const currentResult = await this.getCircuit(endpointKey);
    if (await currentResult.isErr()) {
      return Err(await currentResult.unwrapErr());
    }
    const current = await currentResult.unwrap();
    const firstFailureAtMs = current.firstFailureAtMs ?? nowMs;
    const shouldOpen = current.status === 'open' || nowMs - firstFailureAtMs >= openAfterMs;
    const updated: EndpointCircuit = {
      endpointKey,
      status: shouldOpen ? 'open' : 'closed',
      firstFailureAtMs,
      lastFailureAtMs: nowMs,
      ...(shouldOpen ? { openedAtMs: current.openedAtMs ?? nowMs } : {}),
    };
    try {
      await this.redis.set(circuitKey(endpointKey), JSON.stringify(updated));
      return Ok(updated);
    } catch (error) {
      return Err(redisFailure('record-endpoint-failure', error));
    }
  }

  async closeCircuit(endpointKey: string): Promise<Result<EndpointCircuit, StorageFailure>> {
    const updated = closedCircuit(endpointKey);
    try {
      await this.redis.set(circuitKey(endpointKey), JSON.stringify(updated));
      return Ok(updated);
    } catch (error) {
      return Err(redisFailure('close-circuit', error));
    }
  }

  async setCircuitStatus(
    endpointKey: string,
    status: CircuitStatus,
    nowMs: number,
  ): Promise<Result<EndpointCircuit, StorageFailure>> {
    if (status === 'closed') {
      return this.closeCircuit(endpointKey);
    }
    const currentResult = await this.getCircuit(endpointKey);
    if (await currentResult.isErr()) {
      return Err(await currentResult.unwrapErr());
    }
    const current = await currentResult.unwrap();
    const updated: EndpointCircuit = {
      ...current,
      endpointKey,
      status: 'open',
      firstFailureAtMs: current.firstFailureAtMs ?? nowMs,
      lastFailureAtMs: current.lastFailureAtMs ?? nowMs,
      openedAtMs: current.openedAtMs ?? nowMs,
    };
    try {
      await this.redis.set(circuitKey(endpointKey), JSON.stringify(updated));
      return Ok(updated);
    } catch (error) {
      return Err(redisFailure('set-circuit-status', error));
    }
  }

  async listEventMonths(tenantId: string): Promise<Result<readonly string[], StorageFailure>> {
    try {
      return Ok((await this.redis.smembers(monthIndexKey(tenantId))).sort());
    } catch (error) {
      return Err(redisFailure('list-event-months', error));
    }
  }

  async beginEventMonthArchive(
    request: BeginEventMonthArchiveRequest,
  ): Promise<Result<EventMonthArchiveLease, StorageFailure>> {
    if (
      !/^\d{4}-(?:0[1-9]|1[0-2])$/.test(request.month) ||
      request.leaseToken.length === 0 ||
      !Number.isSafeInteger(request.nowMs) ||
      request.nowMs < 0 ||
      !Number.isSafeInteger(request.leaseMs) ||
      request.leaseMs < 1
    ) {
      return Err(redisFailure('begin-event-month-archive', 'invalid archive lease request', 'invalid-data'));
    }
    try {
      const raw = (await this.redis.eval(
        beginArchiveScript,
        3,
        archiveStateKey(request.tenantId, request.month),
        eventStreamKey(request.tenantId, request.month),
        activeMonthJobsKey(request.tenantId, request.month),
        request.leaseToken,
        String(request.nowMs),
        String(request.leaseMs),
      )) as Array<number | string>;
      const status = Number(raw[0]);
      if (status !== 1) {
        const message =
          status === -2
            ? 'event month still has active obligations'
            : status === -3
              ? 'event month not found'
              : 'event month already has an active archive lease';
        return Err(redisFailure('begin-event-month-archive', message, status === -3 ? 'invalid-data' : 'conflict'));
      }
      const phase = raw[2] === 'deleting' ? 'deleting' : 'exporting';
      const manifestValue = String(raw[5] ?? '');
      return Ok({
        tenantId: request.tenantId,
        month: request.month,
        leaseToken: request.leaseToken,
        version: Number(raw[1]),
        phase,
        leasedUntilMs: Number(raw[3]),
        snapshotCursor: String(raw[4]),
        ...(manifestValue.length === 0 ? {} : { manifest: JSON.parse(manifestValue) as EventMonthArchiveManifest }),
      });
    } catch (error) {
      return Err(redisFailure('begin-event-month-archive', error));
    }
  }

  async renewEventMonthArchive(
    lease: EventMonthArchiveLease,
    nowMs: number,
    leaseMs: number,
  ): Promise<Result<EventMonthArchiveLease, StorageFailure>> {
    if (!Number.isSafeInteger(nowMs) || nowMs < 0 || !Number.isSafeInteger(leaseMs) || leaseMs < 1) {
      return Err(redisFailure('renew-event-month-archive', 'invalid archive lease renewal', 'invalid-data'));
    }
    try {
      const leasedUntilMs = Number(
        await this.redis.eval(
          renewArchiveScript,
          1,
          archiveStateKey(lease.tenantId, lease.month),
          lease.phase,
          String(lease.version),
          lease.leaseToken,
          String(nowMs),
          String(leaseMs),
        ),
      );
      return leasedUntilMs > 0
        ? Ok({ ...lease, leasedUntilMs })
        : Err(redisFailure('renew-event-month-archive', 'archive lease is stale or expired', 'conflict'));
    } catch (error) {
      return Err(redisFailure('renew-event-month-archive', error));
    }
  }

  private async assertArchiveLease(lease: EventMonthArchiveLease): Promise<boolean> {
    return (
      Number(
        await this.redis.eval(
          assertArchiveLeaseScript,
          1,
          archiveStateKey(lease.tenantId, lease.month),
          lease.phase,
          String(lease.version),
          lease.leaseToken,
          String(lease.leasedUntilMs),
        ),
      ) === 1
    );
  }

  async readEventMonthArchivePage(
    lease: EventMonthArchiveLease,
    cursor: string | undefined,
    limit: number,
    maxBytes: number,
  ): Promise<Result<EventMonthArchivePage, StorageFailure>> {
    if (
      lease.phase !== 'exporting' ||
      (cursor !== undefined && !/^\d+-\d+$/.test(cursor)) ||
      validPageLimit(limit) === null ||
      !Number.isSafeInteger(maxBytes) ||
      maxBytes < 1
    ) {
      return Err(redisFailure('read-event-month-archive-page', 'invalid archive page request', 'invalid-data'));
    }
    try {
      if (!(await this.assertArchiveLease(lease))) {
        return Err(redisFailure('read-event-month-archive-page', 'archive lease is stale', 'conflict'));
      }
      const entries = await this.redis.xrange(
        eventStreamKey(lease.tenantId, lease.month),
        cursor === undefined ? '-' : `(${cursor}`,
        lease.snapshotCursor,
        'COUNT',
        limit,
      );
      const records: EventArchiveRecord[] = [];
      let body = encodeEventArchivePage(this.landscape, lease.tenantId, lease.month, lease.version, records);
      let firstCursor: string | undefined;
      let lastCursor: string | undefined;
      for (const [streamId, fields] of entries) {
        const envelopeValue = streamField(fields, 'envelope');
        const eventId = streamField(fields, 'id');
        if (envelopeValue === null || eventId === null) {
          return Err(
            redisFailure('read-event-month-archive-page', 'archive stream entry is incomplete', 'invalid-data'),
          );
        }
        const envelope = decodeEnvelope(envelopeValue);
        const jobs = new Map<string, DeliveryJob>();
        let jobCursor = '0';
        do {
          const scanned = await this.redis.sscan(eventJobsKey(eventId), jobCursor, 'COUNT', DEFAULT_PAGE_LIMIT);
          jobCursor = scanned[0];
          if (scanned[1].length > 0) {
            const values = await this.redis.mget(scanned[1].map(jobKey));
            for (const value of values) {
              if (value !== null) {
                const job = decodeJob(value);
                jobs.set(job.id, job);
              }
            }
          }
          const approximateBytes =
            envelopeValue.length + [...jobs.values()].reduce((total, job) => total + encodeJob(job).length, 0);
          if (approximateBytes > maxBytes) {
            return Err(
              redisFailure(
                'read-event-month-archive-page',
                'one archive record exceeds the configured part bound',
                'invalid-data',
              ),
            );
          }
        } while (jobCursor !== '0');
        const deadLettersByField = new Map<string, DeadLetterEntry>();
        let deadLetterCursor = '0';
        do {
          const scanned = await this.redis.hscan(
            eventDeadLettersKey(eventId),
            deadLetterCursor,
            'COUNT',
            DEFAULT_PAGE_LIMIT,
          );
          deadLetterCursor = scanned[0];
          if (scanned[1].length % 2 !== 0) {
            throw new Error('event dead-letter hash returned an incomplete field/value pair');
          }
          for (let index = 0; index < scanned[1].length; index += 2) {
            const field = scanned[1][index];
            const value = scanned[1][index + 1];
            if (field === undefined || value === undefined) {
              continue;
            }
            deadLettersByField.set(field, JSON.parse(storedDeadLetterValue(value).payload) as DeadLetterEntry);
          }
        } while (deadLetterCursor !== '0');
        const deadLetters: DeadLetterEntry[] = [];
        for (const [, deadLetter] of [...deadLettersByField].sort(([left], [right]) => left.localeCompare(right))) {
          deadLetters.push(deadLetter);
          const recordBody = encodeEventArchivePage(this.landscape, lease.tenantId, lease.month, lease.version, [
            { envelope, jobs: [...jobs.values()], deadLetters },
          ]);
          if (recordBody.byteLength > maxBytes) {
            return Err(
              redisFailure(
                'read-event-month-archive-page',
                'one archive record exceeds the configured part bound',
                'invalid-data',
              ),
            );
          }
        }
        const candidate: EventArchiveRecord = {
          envelope,
          jobs: [...jobs.values()],
          deadLetters,
        };
        const encoded = encodeEventArchivePage(this.landscape, lease.tenantId, lease.month, lease.version, [
          ...records,
          candidate,
        ]);
        if (encoded.byteLength > maxBytes) {
          if (records.length === 0) {
            return Err(
              redisFailure(
                'read-event-month-archive-page',
                'one archive record exceeds the configured part bound',
                'invalid-data',
              ),
            );
          }
          break;
        }
        records.push(candidate);
        body = encoded;
        firstCursor ??= streamId;
        lastCursor = streamId;
      }
      if (!(await this.assertArchiveLease(lease))) {
        return Err(redisFailure('read-event-month-archive-page', 'archive lease changed during paging', 'conflict'));
      }
      const jobCount = records.reduce((total, record) => total + record.jobs.length, 0);
      const deadLetterCount = records.reduce((total, record) => total + record.deadLetters.length, 0);
      const hasMore =
        lastCursor !== undefined &&
        lastCursor !== lease.snapshotCursor &&
        (records.length < entries.length || entries.length === limit);
      return Ok({
        body,
        eventCount: records.length,
        jobCount,
        deadLetterCount,
        ...(firstCursor === undefined ? {} : { firstCursor }),
        ...(lastCursor === undefined ? {} : { lastCursor }),
        ...(hasMore && lastCursor !== undefined ? { nextCursor: lastCursor } : {}),
      });
    } catch (error) {
      return Err(redisFailure('read-event-month-archive-page', error));
    }
  }

  async sealEventMonthArchive(
    lease: EventMonthArchiveLease,
    manifest: EventMonthArchiveManifest,
  ): Promise<Result<EventMonthArchiveLease, StorageFailure>> {
    try {
      const sealed = Number(
        await this.redis.eval(
          sealArchiveScript,
          1,
          archiveStateKey(lease.tenantId, lease.month),
          String(lease.version),
          lease.leaseToken,
          String(lease.leasedUntilMs),
          JSON.stringify(manifest),
        ),
      );
      return sealed === 1
        ? Ok({ ...lease, phase: 'deleting', manifest })
        : Err(redisFailure('seal-event-month-archive', 'archive lease is stale', 'conflict'));
    } catch (error) {
      return Err(redisFailure('seal-event-month-archive', error));
    }
  }

  async deleteEventMonthArchivePage(
    lease: EventMonthArchiveLease,
    limit: number,
  ): Promise<Result<EventMonthDeletionPage, StorageFailure>> {
    const boundedLimit = validPageLimit(limit);
    if (lease.phase !== 'deleting' || boundedLimit === null) {
      return Err(redisFailure('delete-event-month-archive-page', 'invalid archive deletion request', 'invalid-data'));
    }
    try {
      const entries = await this.redis.xrange(
        eventStreamKey(lease.tenantId, lease.month),
        '-',
        lease.snapshotCursor,
        'COUNT',
        1,
      );
      const first = entries[0];
      if (first === undefined) {
        return Ok({ deletedEvents: 0, deletedJobs: 0, done: true });
      }
      const [streamId, fields] = first;
      const eventId = streamField(fields, 'id');
      if (eventId === null) {
        return Err(
          redisFailure('delete-event-month-archive-page', 'archive stream entry is incomplete', 'invalid-data'),
        );
      }
      const ids = (await this.redis.srandmember(eventJobsKey(eventId), boundedLimit)) as string[];
      const jobValues = ids.length === 0 ? [] : await this.redis.mget(ids.map(jobKey));
      const keys = [
        archiveStateKey(lease.tenantId, lease.month),
        eventKey(eventId),
        eventStreamKey(lease.tenantId, lease.month),
        eventJobsKey(eventId),
        READY_QUEUE_KEY,
        RETRY_QUEUE_KEY,
        DELIVERY_CLAIMS_KEY,
        DELIVERY_CLAIM_EXPIRIES_KEY,
        PAUSED_EXPIRIES_KEY,
        activeMonthJobsKey(lease.tenantId, lease.month),
        eventDeadLettersKey(eventId),
        retainedEventIndexKey(lease.tenantId),
        ...ids.flatMap((id, index) => {
          const value = jobValues[index];
          const endpointId = value === null || value === undefined ? '__missing__' : decodeJob(value).endpointId;
          return [jobKey(id), endpointDeadLettersKey(lease.tenantId, endpointId)];
        }),
      ];
      const raw = (await this.redis.eval(
        deleteArchivePageScript,
        keys.length,
        ...keys,
        String(lease.version),
        lease.leaseToken,
        String(lease.leasedUntilMs),
        streamId,
        eventId,
        String(ids.length),
        ...ids,
      )) as Array<number | string>;
      if (Number(raw[0]) !== 1) {
        return Err(redisFailure('delete-event-month-archive-page', 'archive lease is stale', 'conflict'));
      }
      const deletedEvents = Number(raw[1]);
      const done = deletedEvents === 1 && (await this.redis.xlen(eventStreamKey(lease.tenantId, lease.month))) === 0;
      return Ok({ deletedEvents, deletedJobs: ids.length, done });
    } catch (error) {
      return Err(redisFailure('delete-event-month-archive-page', error));
    }
  }

  async completeEventMonthArchive(lease: EventMonthArchiveLease): Promise<Result<void, StorageFailure>> {
    try {
      const completed = Number(
        await this.redis.eval(
          completeArchiveScript,
          8,
          archiveStateKey(lease.tenantId, lease.month),
          eventStreamKey(lease.tenantId, lease.month),
          attemptStreamKey(lease.tenantId, lease.month),
          dlqKey(lease.tenantId, lease.month),
          activeMonthJobsKey(lease.tenantId, lease.month),
          pausedMonthKey(lease.tenantId, lease.month),
          monthIndexKey(lease.tenantId),
          dlqMonthIndexKey(lease.tenantId),
          String(lease.version),
          lease.leaseToken,
          lease.month,
        ),
      );
      return completed === 1
        ? Ok(undefined)
        : Err(redisFailure('complete-event-month-archive', 'archive deletion is incomplete or stale', 'conflict'));
    } catch (error) {
      return Err(redisFailure('complete-event-month-archive', error));
    }
  }

  async abortEventMonthArchive(lease: EventMonthArchiveLease): Promise<Result<void, StorageFailure>> {
    try {
      const aborted = Number(
        await this.redis.eval(
          abortArchiveScript,
          1,
          archiveStateKey(lease.tenantId, lease.month),
          String(lease.version),
          lease.leaseToken,
        ),
      );
      return aborted === 1
        ? Ok(undefined)
        : Err(redisFailure('abort-event-month-archive', 'archive lease is stale or already sealed', 'conflict'));
    } catch (error) {
      return Err(redisFailure('abort-event-month-archive', error));
    }
  }
}
