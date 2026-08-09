import { z } from 'zod';

const seedRecordSchema = z
  .object({
    id: z.string().trim().min(1),
    value: z.string(),
  })
  .strict();

const seedRecordsSchema = z.array(seedRecordSchema);
export type SeedRecord = z.infer<typeof seedRecordSchema>;

export function parseSeedRecords(value: unknown): readonly SeedRecord[] {
  return seedRecordsSchema.parse(value);
}

export function selectMissingSeedRecords(
  records: readonly SeedRecord[],
  existingIds: ReadonlySet<string>,
): readonly SeedRecord[] {
  return records.filter(record => !existingIds.has(record.id));
}
