// ─── DOMAIN WIRING · the standard-config export surface ─────────────────────────────────────────
// Infra preset schemas (C0-frozen key-for-key across bun / dotnet / go).
export * from './lib/presets/postgres';
export * from './lib/presets/redis';
export * from './lib/presets/cache';
export * from './lib/presets/kv';
export * from './lib/presets/storage';
// Keyed multi-instance helpers + the shared error.
export * from './lib/presets/keyed';
// Registrar — plug presets into a lib/bun/config registry.
export * from './lib/register';
// The one S3-compatible block-storage implementation.
export * from './adapters/s3-block-storage';
// ─── END DOMAIN WIRING ──────────────────────────────────────────────────────────────────────────
