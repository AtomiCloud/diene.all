import type { z } from 'zod';

/**
 * Thrown when the FINAL merged configuration fails schema validation. Carries
 * the aggregated, human-readable per-path issues. Validation is fail-fast at
 * startup and runs on the final layer only — intermediate tiers are never
 * validated.
 */
export class ConfigValidationError extends Error {
  readonly issues: readonly string[];

  constructor(issues: readonly string[]) {
    super(`configuration validation failed on the final merged layer: ${issues.join('; ')}`);
    this.name = 'ConfigValidationError';
    this.issues = issues;
  }
}

/** Parse `value` against `schema`, throwing `ConfigValidationError` on failure. */
export const validateConfig = <T>(schema: z.ZodType<T>, value: unknown): T => {
  const parsed = schema.safeParse(value);
  if (parsed.success) return parsed.data;
  const issues = parsed.error.issues.map(issue => {
    const path = issue.path.length > 0 ? issue.path.map(String).join('.') : '(root)';
    return `${path}: ${issue.message}`;
  });
  throw new ConfigValidationError(issues);
};
