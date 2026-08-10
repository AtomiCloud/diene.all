/**
 * Build-time env tier (pure).
 *
 * The bundler injects a JSON payload (DefinePlugin) that sits between the YAML
 * tiers and runtime env in the config precedence chain. Parsing it is pure
 * string→record logic with no I/O, so it lives here rather than in the config
 * adapter: the adapter reads `process.env` and hands the raw string over.
 *
 * A payload that is absent, empty, unparseable, or not a JSON object degrades to
 * NO build tier. Failing the boot over a malformed injected payload would take
 * the whole app down for a build-system defect the running process cannot fix.
 */
export const parseBuildTimeEnv = (injected: string | undefined): Record<string, string> => {
  if (typeof injected !== 'string' || injected === '') return {};
  try {
    const parsed: unknown = JSON.parse(injected);
    return typeof parsed === 'object' && parsed !== null ? (parsed as Record<string, string>) : {};
  } catch {
    return {};
  }
};
