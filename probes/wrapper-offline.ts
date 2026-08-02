// Local-offline indicators. Each is a precise substring matched against the
// command's combined stderr+stdout (whitespace-collapsed, lowercased). They come
// from the real network stacks these probes drive — Go's net/http and crypto/tls
// (helm), skopeo's container-registry client, and curl-style resolvers.
//
// Be conservative: ONLY unambiguous LOCAL-offline evidence may classify a probe
// inapplicable — DNS resolution failure and routing failure. Every other failure
// must stay broken, because it implies the peer/service was reachable or the cause
// is indistinguishable from a live-but-slow remote:
//  - HTTP status lines, script errors, and semantic failures (404/401, "command
//    not found", "no such file or directory", "chart ... not found") mean the host
//    was reached or the failure was local.
//  - Reachable-peer failures (`connection refused`, `connection reset by peer`,
//    `connection reset`) mean a host answered but the port/service was down — the
//    network path itself exists.
//  - Remote timeouts (`tls handshake timeout`, `i/o timeout`, `context deadline
//    exceeded`) are indistinguishable from a slow-but-live remote; without proof
//    of a local-offline distinction they stay broken.
//  - A bare `dial tcp` indicator is intentionally omitted: it prefixes both
//    resolver failures (caught via `no such host` below) and reachable-peer
//    connect failures, so it is too broad to trust on its own.
const CONNECTIVITY_INDICATORS = [
  'no such host', // Go DNS resolution: `lookup <host>: no such host`
  'could not resolve host', // curl/wget resolver failure
  'network is unreachable', // routing: no route to the destination network
  'network unreachable',
] as const;

export function isConnectivityFailure(detail: string): boolean {
  const haystack = detail.toLowerCase().replace(/\s+/g, ' ');
  return CONNECTIVITY_INDICATORS.some(indicator => haystack.includes(indicator));
}

// The CyanPrint "inapplicable" signal, kept as a faithful local copy of the
// engine contract at @cyanprint/contracts (probe.ts: `probeInapplicable` /
// `isProbeInapplicable`). An ordinary Error carries a non-enumerable
// `cyanprintProbeInapplicable = true` property; non-enumerable so it never leaks
// into serialized logs or `Error.prototype.toString`, while the probe runner
// reads it by property access and records the probe `invalid` (inapplicable /
// offline) rather than `broken`.
//
// This is local rather than `import { probeInapplicable } from
// '@cyanprint/contracts'` because a consuming probe cannot resolve that package
// at runtime: cyanprint loads a locally-authored probe by direct dynamic
// `import()` (engine `load-probe.ts`), and both cyanprint 4.9.0 and plain `bun`
// fail with `Cannot find module '@cyanprint/contracts'` for a local probe that
// value-imports it (verified). The whole consuming codebase imports only types
// from `@cyanprint/contracts`, and the engine detects the marker across module
// realms by property name (never `instanceof`), so this construction is read
// exactly like the official one. Keep it byte-for-byte in sync with the contract.
const PROBE_INAPPLICABLE_MARKER = 'cyanprintProbeInapplicable';

export function probeInapplicable(reason: string): Error {
  const error = new Error(reason);
  Object.defineProperty(error, PROBE_INAPPLICABLE_MARKER, { value: true, enumerable: false });
  return error;
}

export function isProbeInapplicable(value: unknown): boolean {
  return (
    typeof value === 'object' &&
    value !== null &&
    (value as Record<string, unknown>)[PROBE_INAPPLICABLE_MARKER] === true
  );
}

// Run a live-network command and expect it green. On a non-zero exit, if the
// output is a precisely verified connectivity failure, throw the CyanPrint
// inapplicable signal so an offline environment does not register as a broken
// probe; every other failure stays a normal (broken) error. Use this only for
// probes whose green path genuinely requires the public network.
export async function expectGreenOrOffline(repo: any, command: string, label: string): Promise<void> {
  const result = await repo.exec(command, { timeoutMs: 240000 });
  if (result.exitCode === 0) {
    return;
  }
  const detail = `${result.stderr || ''}\n${result.stdout || ''}`;
  if (isConnectivityFailure(detail)) {
    throw probeInapplicable(
      `${label} is inapplicable: verified offline (connectivity failure) for: ${command}\n${detail.trim()}`,
    );
  }
  throw new Error(`${label} failed on the healthy repo: ${result.stderr || result.stdout}`);
}
