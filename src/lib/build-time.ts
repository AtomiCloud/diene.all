/**
 * Build-time value map.
 *
 * Build-time is a dimension for ALL app types (shared/client/server crossed with
 * build-time/runtime). For bundled targets, the inlineable (client/build-time)
 * subset is frozen into the artifact by a DefinePlugin-style static injection.
 * The bundler (e.g. nextjs) owns the DefinePlugin wiring; this lib owns the
 * VALUE MAP that wiring injects.
 *
 * `buildTimeValueMap` scans a flat env record for the prefixed, non-blank
 * variables that make up that subset. Blank values are excluded (M33): since
 * secrets only ever materialize as runtime env, a value absent here is simply
 * not inlined.
 */
export const buildTimeValueMap = (env: Record<string, string | undefined>, prefix: string): Record<string, string> => {
  const map: Record<string, string> = {};
  for (const [key, value] of Object.entries(env)) {
    if (key.startsWith(prefix) && value !== undefined && value !== '') {
      map[key] = value;
    }
  }
  return map;
};
