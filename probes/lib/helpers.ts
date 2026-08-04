// Captured-env pilot (E4). Every probe command that needs a development shell pays a
// fresh `nix develop` evaluation — measured at 2-16 s — on each of the ~1,300 executions
// a green workspace ledger performs. When PROBE_CAPTURED_ENV names a directory holding
// `nix print-dev-env` captures (one `<shell>.sh` per shell), shell entry is replaced by
// sourcing the capture for that shell. The rewrite is opt-in: with the variable unset
// the bytes handed to repo.exec are identical to what they were before this existed.
//
// `dev-shell` and `direnv` are exempt because entering the shell is the mechanism those
// two arms exist to prove; sourcing a capture would leave them asserting nothing.
const CAPTURED_ENV_EXEMPT_LABELS = new Set(['dev-shell', 'direnv']);

// The only shape the corpus uses, with and without --no-write-lock-file. Everything
// after `-c ` is the command word list and is carried through untouched, which is what
// keeps the `bash -lc '<quoted>'` nesting the corpus already relies on intact.
const DEV_SHELL_ENTRY = /nix develop (?:--no-write-lock-file )?\.#([A-Za-z0-9_.-]+) -c /g;

// A constant script with nothing interpolated into it: the capture path and the original
// command arrive as positional parameters, so no quoting of ours can collide with quoting
// of the command's. Missing capture is a loud 127 rather than a silent run in the ambient
// environment, because a probe that quietly stopped entering a shell would still be green.
const SOURCE_AND_EXEC =
  'bash -c \'captured="$1"; shift; ' +
  '[ -r "$captured" ] || { echo "captured env is not readable: $captured" >&2; exit 127; }; ' +
  '. "$captured"; exec "$@"\' probe-captured-env ';

function quoteForShell(value: string): string {
  return `'${value.replaceAll("'", `'"'"'`)}'`;
}

export function capturedEnvCommand(
  command: string,
  label?: string,
  envDir: string | undefined = process.env.PROBE_CAPTURED_ENV,
): string {
  if (!envDir || (label !== undefined && CAPTURED_ENV_EXEMPT_LABELS.has(label))) {
    return command;
  }
  return command.replace(
    DEV_SHELL_ENTRY,
    (_match, shell: string) => `${SOURCE_AND_EXEC}${quoteForShell(`${envDir}/${shell}.sh`)} `,
  );
}

export async function expectGreen(repo: any, command: string, label: string): Promise<void> {
  const result = await repo.exec(capturedEnvCommand(command, label), { timeoutMs: 240000 });
  if (result.exitCode !== 0) {
    throw new Error(`${label} failed on the healthy repo: ${result.stderr || result.stdout}`);
  }
}

export async function expectRed(repo: any, command: string, label: string): Promise<void> {
  const result = await repo.exec(capturedEnvCommand(command, label), { timeoutMs: 240000 });
  if (result.exitCode === 0) {
    throw new Error(`${label} stayed green after sabotage`);
  }
}
