// Shared sandbox-script runner for the go-consumer rows.
//
// WHY A SCRIPT FILE AND NOT NESTED SHELL QUOTING (PROBES §2, authoring rule):
// escaped quotes inside a single-quoted `bash -c` are literal, and an unquoted
// `>` silently becomes a redirect that blanks the check while the transcript
// still reads green. Every non-trivial gate body therefore lives in a real
// script, materialised as a whole file and executed as a whole file.
//
// WHY $TMPDIR AND NOT THE SANDBOX TREE: a probe-authored file inside the
// repository would legitimately redden the gofumpt / shellcheck / prettier /
// executable-shells controls co-selected with the row, and would also be swept
// by the deadcode gates. The script rides base64 on the command line, is decoded
// into a mktemp file outside the repository, and is removed afterwards.
//
// WHY STDIN IS DETACHED: `docker compose up` / `docker compose run` and `k3d
// cluster create` attach to stdin. Piping the script into `bash` over stdin lets
// a stage drain the remaining bytes, silently swallowing the trailing assertions
// so the row exits 0 without ever asserting.
//
// GAP-5 SWEEP (PROBES Gap 5, sanctioned chain-side mitigation): EVERY helper on
// this branch that builds a `sandbox: {snapshot: 'git'}` run and then executes an
// SCM-consulting command restores the `origin` remote URL if absent. The
// snapshot repository is constructed with no remote, so `git remote get-url
// origin` and anything resolving the repository through git fail in the sandbox
// while passing on a direct checkout. This is gate-environment setup: the
// property under test is chart/task validity, not remote presence.

// The fetch URL of the authoritative repository. Added as remote METADATA only;
// nothing here ever fetches from it.
export const ORIGIN_URL = 'https://github.com/AtomiCloud/diene.all.git';

export const GAP5_PREAMBLE = `# PROBES Gap 5: snapshot=git builds the run repository with NO remote.
git remote get-url origin >/dev/null 2>&1 || git remote add origin ${ORIGIN_URL}
`;

export type SandboxRunOptions = {
  timeoutMs?: number;
  shell?: string;
};

export function sandboxScriptCommand(body: string, shell = 'ci'): string {
  const script = `set -euo pipefail\n${GAP5_PREAMBLE}${body}`;
  const encoded = Buffer.from(script, 'utf8').toString('base64');
  return `nix develop .#${shell} -c bash -lc 'f="$(mktemp)"; echo ${encoded} | base64 -d >"$f"; bash "$f" </dev/null; r=$?; rm -f "$f"; exit $r'`;
}

export type SandboxRunResult = {
  exitCode: number;
  stdout: string;
  stderr: string;
  transcript: string;
};

export async function runSandboxScript(
  repo: any,
  body: string,
  options: SandboxRunOptions = {},
): Promise<SandboxRunResult> {
  const result = await repo.exec(sandboxScriptCommand(body, options.shell ?? 'ci'), {
    timeoutMs: options.timeoutMs ?? 900000,
  });
  return {
    exitCode: result.exitCode,
    stdout: result.stdout ?? '',
    stderr: result.stderr ?? '',
    transcript: `${result.stdout ?? ''}\n${result.stderr ?? ''}`,
  };
}

// Assert on printed VALUES, never on a bare exit 0: a PASS branch reached by a
// command that produced NO OUTPUT is not a guard. `markers` are the strings the
// healthy run must have actually printed.
export async function expectScriptGreen(
  repo: any,
  body: string,
  label: string,
  markers: string[],
  options: SandboxRunOptions = {},
): Promise<SandboxRunResult> {
  const result = await runSandboxScript(repo, body, options);
  if (result.exitCode !== 0) {
    throw new Error(`${label} failed on the healthy repo:\n${result.transcript}`);
  }
  if (result.transcript.trim().length === 0) {
    throw new Error(`${label} exited 0 but printed nothing — the check never ran`);
  }
  const missing = markers.filter(marker => !result.transcript.includes(marker));
  if (missing.length > 0) {
    throw new Error(
      `${label} exited 0 without printing ${missing.map(m => JSON.stringify(m)).join(', ')} — refusing a silent pass:\n${result.transcript}`,
    );
  }
  return result;
}

export async function expectScriptRed(
  repo: any,
  body: string,
  label: string,
  options: SandboxRunOptions = {},
): Promise<SandboxRunResult> {
  const result = await runSandboxScript(repo, body, options);
  if (result.exitCode === 0) {
    throw new Error(`${label} stayed green after sabotage:\n${result.transcript}`);
  }
  return result;
}
