export function slugify(input: string): string {
  return input
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

export class NamespacedKeyValidationError extends Error {
  constructor(
    readonly field: 'namespace' | 'key',
    readonly reason: string,
  ) {
    super(`${field} ${reason}`);
    this.name = 'NamespacedKeyValidationError';
  }
}

export function namespacedKey(namespace: string, key: string): string {
  const ns = slugify(namespace);
  const k = slugify(key);
  if (ns === '') throw new NamespacedKeyValidationError('namespace', 'must not be empty');
  if (k === '') throw new NamespacedKeyValidationError('key', 'must not be empty');
  return `${ns}:${k}`;
}
