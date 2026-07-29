import { z } from 'zod';
import type { ConsoleResult } from './model.ts';

const identifier = z.string().min(1).max(256);
const timestampMilliseconds = z.number().int().nonnegative().safe();
const nonnegativeInteger = z.number().int().nonnegative().safe();
const eventStatus = z.enum(['completed', 'dead-letter', 'paused', 'pending', 'retrying']);

const eventSummarySchema = z
  .object({
    id: identifier,
    tenantId: identifier,
    routeId: identifier,
    provider: z.string().min(1).max(128),
    landscape: identifier,
    receivedAtMs: timestampMilliseconds,
    providerEventId: z.string().max(1_024).optional(),
    providerTimestampMs: timestampMilliseconds.optional(),
    providerSequence: z.string().max(1_024).optional(),
    status: eventStatus,
    endpointIds: z.array(identifier).max(1_024),
    attemptCount: nonnegativeInteger,
    nextDueAtMs: timestampMilliseconds.optional(),
  })
  .strict();

const attemptSchema = z
  .object({
    number: z.number().int().positive().safe(),
    attemptedAtMs: timestampMilliseconds,
    address: z.string().min(1).max(8_192),
    statusCode: z.number().int().min(100).max(599).optional(),
    transportError: z.string().max(2_048).optional(),
    replay: z.boolean(),
  })
  .strict();

const jobSchema = z
  .object({
    id: identifier,
    eventId: identifier,
    endpointId: identifier,
    address: z.string().min(1).max(8_192),
    addressKind: z.enum(['canonical', 'external', 'local']),
    createdAtMs: timestampMilliseconds,
    dueAtMs: timestampMilliseconds,
    retryWindowMs: nonnegativeInteger,
    status: z.enum(['completed', 'dead-letter', 'paused', 'pending']),
    attempts: z.array(attemptSchema).max(10_000),
    misrouteRefreshes: nonnegativeInteger,
    replayCount: nonnegativeInteger,
  })
  .strict();

const healthSchema = z
  .object({
    landscape: identifier,
    status: z.enum(['degraded', 'healthy']),
    checkedAtMs: timestampMilliseconds,
    activeGeneration: nonnegativeInteger.nullable(),
    compiledAtMs: timestampMilliseconds.optional(),
    sourceRevision: z.string().max(2_048).optional(),
    supervisor: z.enum(['running', 'stopped', 'unknown']),
  })
  .strict();

const eventListSchema = z
  .object({
    landscape: identifier,
    tenantId: identifier,
    items: z.array(eventSummarySchema).max(200),
    nextCursor: z.string().max(256).optional(),
  })
  .strict();

const eventDetailSchema = z
  .object({
    event: eventSummarySchema,
    headers: z.record(z.string().max(256), z.string().max(8_192)),
    verificationMetadata: z.record(z.string().max(256), z.string().max(8_192)),
    rawBodyBase64: z
      .string()
      .max(2_796_208)
      .regex(/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/),
    jobs: z.array(jobSchema).max(1_024),
  })
  .strict();

const deadLetterSchema = z
  .object({
    landscape: identifier,
    tenantId: identifier,
    eventId: identifier,
    endpointId: identifier,
    jobId: identifier,
    provider: z.string().min(1).max(128).optional(),
    exhaustedAtMs: timestampMilliseconds,
    reason: z.string().min(1).max(2_048),
    attemptCount: nonnegativeInteger,
    finalOutcome: z.union([z.number().int().min(100).max(599), z.string().max(2_048)]).optional(),
  })
  .strict();

const deadLetterListSchema = z
  .object({
    landscape: identifier,
    tenantId: identifier,
    items: z.array(deadLetterSchema).max(10_000),
  })
  .strict();

const actionReceiptSchema = z
  .object({
    actionId: identifier,
    action: z.enum(['circuit-reenabled', 'endpoint-replayed', 'event-replayed']),
    landscape: identifier,
    tenantId: identifier,
    acceptedAtMs: timestampMilliseconds,
    affectedCount: nonnegativeInteger,
  })
  .strict();

export type LocalLandscapeHealth = z.infer<typeof healthSchema>;
export type LocalLandscapeEventSummary = z.infer<typeof eventSummarySchema>;
export type LocalLandscapeEventList = z.infer<typeof eventListSchema>;
export type LocalLandscapeEventDetail = z.infer<typeof eventDetailSchema>;
export type LocalLandscapeDeadLetter = z.infer<typeof deadLetterSchema>;
export type LocalLandscapeDeadLetterList = z.infer<typeof deadLetterListSchema>;
export type LocalLandscapeActionReceipt = z.infer<typeof actionReceiptSchema>;

const parse = <Value>(schema: z.ZodType<Value>, input: unknown, label: string): ConsoleResult<Value> => {
  const parsed = schema.safeParse(input);
  return parsed.success
    ? { ok: true, value: parsed.data }
    : {
        ok: false,
        error: {
          kind: 'unavailable',
          title: 'Landscape response rejected',
          detail: `The ${label} response did not match the authenticated DTO contract.`,
        },
      };
};

export const parseLocalLandscapeHealth = (input: unknown): ConsoleResult<LocalLandscapeHealth> =>
  parse(healthSchema, input, 'health');

export const parseLocalLandscapeEventList = (input: unknown): ConsoleResult<LocalLandscapeEventList> =>
  parse(eventListSchema, input, 'event list');

export const parseLocalLandscapeEventDetail = (input: unknown): ConsoleResult<LocalLandscapeEventDetail> =>
  parse(eventDetailSchema, input, 'event detail');

export const parseLocalLandscapeDeadLetterList = (input: unknown): ConsoleResult<LocalLandscapeDeadLetterList> =>
  parse(deadLetterListSchema, input, 'dead-letter list');

export const parseLocalLandscapeActionReceipt = (input: unknown): ConsoleResult<LocalLandscapeActionReceipt> =>
  parse(actionReceiptSchema, input, 'action');
