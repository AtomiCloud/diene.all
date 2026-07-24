// ─── DOMAIN WIRING · the standard-config export surface ─────────────────────────────────────────
// Infra preset schemas (C0-frozen key-for-key across bun / dotnet / go).
export * from './presets/postgres';
export * from './presets/redis';
export * from './presets/cache';
export * from './presets/kv';
export * from './presets/storage';
// Keyed multi-instance helpers + the shared error.
export * from './presets/keyed';
// Registrar — plug presets into a lib/bun/config registry.
export * from './register';
// The one S3-compatible block-storage implementation.
export * from './adapters/s3-block-storage';
// ─── END DOMAIN WIRING ──────────────────────────────────────────────────────────────────────────
