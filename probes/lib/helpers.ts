export async function expectGreen(repo: any, command: string, label: string): Promise<void> {
  const result = await repo.exec(command, { timeoutMs: 240000 });
  if (result.exitCode !== 0) {
    throw new Error(`${label} failed on the healthy repo: ${result.stderr || result.stdout}`);
  }
}

export async function expectRed(repo: any, command: string, label: string): Promise<void> {
  const result = await repo.exec(command, { timeoutMs: 240000 });
  if (result.exitCode === 0) {
    throw new Error(`${label} stayed green after sabotage`);
  }
}

// Credible connectivity-failure indicators. Each is a precise substring matched
// against the command's combined stderr+stdout (whitespace-collapsed, lowercased).
// They come from the real network stacks these probes drive — Go's net/http and
// crypto/tls (helm), skopeo's container-registry client, and curl-style resolvers.
// HTTP status lines, script errors, and semantic failures deliberately do NOT
// appear here: a 404/401 from a reached registry, "command not found", "no such
// file or directory", or "chart ... not found" all mean the host was reached or
// the failure was local, so the probe must stay broken rather than go inapplicable.
const CONNECTIVITY_INDICATORS = [
  'no such host', // Go DNS resolution: `lookup <host>: no such host`
  'could not resolve host', // curl/wget resolver failure
  'network is unreachable', // routing: no route to the destination network
  'network unreachable',
  'connection refused', // port closed / service down on a reachable host
  'connection reset by peer', // mid-handshake or mid-stream reset
  'connection reset',
  'tls handshake timeout', // crypto/tls: the handshake exceeded its deadline
  'i/o timeout', // net: a read/write deadline elapsed
  'context deadline exceeded', // Go context: the operation's own timeout fired
  'dial tcp', // net.Dialer: covers `dial tcp: lookup` and `dial tcp: connect:`
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

// Restore the sandbox to HEAD and drop the probe's own fixtures. `git clean` is
// scoped to the caller's targets so a probe never removes work it does not own.
// Fixtures are made writable first: a probe that proves read-only package content
// is vendored leaves read-only trees behind, and both `git clean` and a later
// `rm -rf` fail on those unless the permission is restored.
export async function restoreProbeState(repo: any, cleanTargets: readonly string[]): Promise<void> {
  const targets = cleanTargets.join(' ');
  const madeWritable = await repo.exec(
    `for target in ${targets}; do if [ -e "$target" ]; then chmod -R u+w -- "$target" || exit 1; fi; done`,
  );
  if (madeWritable.exitCode !== 0) {
    throw new Error(`could not make probe fixtures writable: ${madeWritable.stderr || madeWritable.stdout}`);
  }
  const restored = await repo.exec('git restore --source=HEAD --staged --worktree -- .');
  if (restored.exitCode !== 0) {
    throw new Error(`could not restore tracked probe state: ${restored.stderr || restored.stdout}`);
  }
  const cleaned = await repo.exec(`git clean -fdx -- ${targets}`);
  if (cleaned.exitCode !== 0) {
    throw new Error(`could not remove untracked probe fixtures: ${cleaned.stderr || cleaned.stdout}`);
  }
}

// Run `body` between two restores: the leading one so a previous probe's residue
// cannot decide this outcome, the trailing one so a failure still hands the next
// probe a clean sandbox.
export async function withCleanProbeState(
  repo: any,
  cleanTargets: readonly string[],
  body: () => Promise<void>,
): Promise<void> {
  await restoreProbeState(repo, cleanTargets);
  try {
    await body();
  } finally {
    await restoreProbeState(repo, cleanTargets);
  }
}
