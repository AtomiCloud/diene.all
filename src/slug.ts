import { Err, Ok, type Result } from '@atomicloud/diene.result';

/**
 * Normalize an arbitrary string into a deterministic kebab-case slug.
 *
 * The transform is: NFKD normalization, combining-mark removal, lowercasing,
 * trimming, and collapsing every run of non-alphanumeric characters into a
 * single hyphen (with leading/trailing hyphens stripped).
 */
export function slugify(input: string): string {
  return input
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

/** Validation failure raised when a namespace or key slugifies to empty. */
export class NamespacedKeyValidationError extends Error {
  constructor(
    readonly field: 'namespace' | 'key',
    readonly reason: string,
  ) {
    super(`${field} ${reason}`);
    this.name = 'NamespacedKeyValidationError';
  }
}

/**
 * Compose a `namespace:key` identifier from slugified parts.
 *
 * This is a total function: it never throws for validation failures. When a
 * part slugifies to empty it returns an `Err` carrying a
 * {@link NamespacedKeyValidationError}; otherwise it returns an `Ok` with the
 * composed identifier.
 */
export function namespacedKey(namespace: string, key: string): Result<string, NamespacedKeyValidationError> {
  const ns = slugify(namespace);
  if (ns === '') {
    return Err<string, NamespacedKeyValidationError>(
      new NamespacedKeyValidationError('namespace', 'must not be empty'),
    );
  }

  const k = slugify(key);
  if (k === '') {
    return Err<string, NamespacedKeyValidationError>(new NamespacedKeyValidationError('key', 'must not be empty'));
  }

  return Ok<string, NamespacedKeyValidationError>(`${ns}:${k}`);
}
