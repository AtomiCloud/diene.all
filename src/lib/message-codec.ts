import { z } from 'zod';

const workerMessageSchema = z
  .object({
    createdAt: z.iso.datetime({ offset: true }),
    id: z.uuid(),
    payload: z.string(),
  })
  .strict();

export type WorkerMessage = z.infer<typeof workerMessageSchema>;

const redisEntrySchema = z.tuple([z.string(), z.array(z.string())]);
const readGroupSchema = z.array(z.tuple([z.string(), z.array(redisEntrySchema)]));
const autoClaimSchema = z.tuple([z.string(), z.array(redisEntrySchema), z.array(z.string()).optional()]);

export interface StreamEnvelope {
  readonly id: string;
  readonly payload: string;
}

export function encodeWorkerMessage(message: WorkerMessage): string {
  return JSON.stringify(workerMessageSchema.parse(message));
}

export function decodeWorkerMessage(value: string): WorkerMessage {
  return workerMessageSchema.parse(JSON.parse(value));
}

export function decodeStreamEntries(value: unknown): readonly StreamEnvelope[] {
  const entries = z.array(redisEntrySchema).parse(value);
  return entries.map(([id, fields]) => {
    const pairs = Array.from(
      { length: Math.floor(fields.length / 2) },
      (_, index) => [fields[index * 2], fields[index * 2 + 1]] as const,
    );
    const payload = pairs.find(([key]) => key === 'payload')?.[1];
    return { id, payload: z.string().parse(payload) };
  });
}

export function decodeReadGroupResponse(value: unknown): readonly StreamEnvelope[] {
  if (value === null) return [];
  return readGroupSchema.parse(value).flatMap(([, entries]) => decodeStreamEntries(entries));
}

export function decodeAutoClaimResponse(value: unknown): readonly StreamEnvelope[] {
  const [, entries] = autoClaimSchema.parse(value);
  return decodeStreamEntries(entries);
}
