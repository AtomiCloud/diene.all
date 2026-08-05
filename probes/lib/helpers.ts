// Captured-env pilot. Every probe command that needs a development shell pays a
// fresh `nix develop` evaluation — measured at 2-16 s — on each of the ~1,300 executions
// a green workspace ledger performs. When PROBE_CAPTURED_ENV names a directory holding
// `nix print-dev-env` captures (one `<shell>.sh` per shell), shell entry is replaced by
// sourcing the capture for that shell. The rewrite is opt-in: with the variable unset
// the bytes handed to repo.exec are identical to what they were before this existed.
//
// `dev-shell` and `direnv` are exempt because entering the shell is the mechanism those
// two arms exist to prove; sourcing a capture would leave them asserting nothing.
const CAPTURED_ENV_EXEMPT_LABELS = new Set(['dev-shell', 'direnv']);
const DEV_SHELL_ONCE_MARKER = '.git/cyanprint-probe-dev-shell-checked';

export const DEV_SHELL_CHAIN =
  'nix develop --no-write-lock-file .#default -c true && nix develop --no-write-lock-file .#ci -c true && ' +
  'nix develop --no-write-lock-file .#cd -c true && nix develop --no-write-lock-file .#releaser -c true';

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

export async function expectGreen(repo: any, command: string, label: string, timeoutMs = 240000): Promise<void> {
  const result = await repo.exec(capturedEnvCommand(command, label), { timeoutMs });
  if (result.exitCode !== 0) {
    throw new Error(`${label} failed on the healthy repo: ${result.stderr || result.stdout}`);
  }
}

/**
 * The atomi/nix and diene/workspace features make the identical promise about
 * this same flake. Probe processes are isolated, but their baseline (and sweep)
 * probes share a sandbox, so keep an engine-private marker in its .git metadata:
 * the first duplicate performs the four REAL shell entries, the second observes
 * that proof. A new sandbox has a fresh .git directory, therefore each phase
 * still evaluates and starts every shell once.
 */
export async function expectDevShellsOnce(repo: any): Promise<void> {
  const seen = await repo.exec(`[ -f ${DEV_SHELL_ONCE_MARKER} ]`);
  if (seen.exitCode === 0) {
    return;
  }
  await expectGreen(repo, DEV_SHELL_CHAIN, 'dev-shell');
  const marked = await repo.exec(`: > ${DEV_SHELL_ONCE_MARKER}`);
  if (marked.exitCode !== 0) {
    throw new Error(`could not persist dev-shell proof: ${marked.stderr || marked.stdout}`);
  }
}

export async function expectRed(repo: any, command: string, label: string): Promise<void> {
  const result = await repo.exec(capturedEnvCommand(command, label), { timeoutMs: 240000 });
  if (result.exitCode === 0) {
    throw new Error(`${label} stayed green after sabotage`);
  }
}

export async function expectRedWithDiagnostic(
  repo: any,
  command: string,
  label: string,
  expected: RegExp,
  timeoutMs = 240000,
): Promise<void> {
  const result = await repo.exec(command, { timeoutMs });
  if (result.exitCode === 0) {
    throw new Error(`${label} stayed green after sabotage`);
  }
  const diagnostic = `${result.stdout}\n${result.stderr}`;
  if (!expected.test(diagnostic)) {
    throw new Error(`${label} failed for the wrong reason; expected ${expected}: ${diagnostic}`);
  }
}

function shellArgument(value: string): string {
  return "'" + value.replaceAll("'", "'\\''") + "'";
}

// Make owned targets writable before restoring them because vendoring probes can leave read-only fixture trees.
export async function restoreProbeState(repo: any, cleanTargets: readonly string[]): Promise<void> {
  if (cleanTargets.length === 0) {
    throw new Error('probe cleanup requires at least one owned target');
  }
  const targets = cleanTargets.map(shellArgument).join(' ');
  const madeWritable = await repo.exec(
    `for target in ${targets}; do if [ -e "$target" ]; then chmod -R u+w -- "$target" || exit 1; fi; done`,
  );
  if (madeWritable.exitCode !== 0) {
    throw new Error(`could not make probe fixtures writable: ${madeWritable.stderr || madeWritable.stdout}`);
  }
  // The worklist comes from HEAD, never from the index. `git ls-files` reads the index, so a
  // STAGED DELETION removes the path from its output, `xargs -0 -r` then runs nothing, and the
  // restore reports success with the deletion still staged — a silent failure. `git ls-tree`
  // reads HEAD, where the path is still present, so a staged deletion is still in the worklist.
  //
  // Each target is classified and handled on its own so no list is re-quoted:
  //  - HEAD knows it  -> restore it from HEAD, scoped to that target. Scoped, not `-- .`: a
  //                      whole-tree restore also reverts uncommitted work the probe does not own,
  //                      which is unsafe the moment anything shares the worktree.
  //  - HEAD does not  -> it can only be a staged addition or untracked fixture, so drop it from
  //                      the index and let the scoped `git clean` below remove it. Restoring it
  //                      from HEAD is impossible and asking git to try is a hard pathspec error.
  //
  // `git ls-tree` exits 0 with empty output for a pathspec HEAD does not match, so classification
  // needs no error suppression: nothing here hides a diagnostic it then draws a conclusion from.
  const restored = await repo.exec(
    `for target in ${targets}; do ` +
      `if [ -n "$(git ls-tree -r --name-only HEAD -- "$target")" ]; then ` +
      `git restore --source=HEAD --staged --worktree -- "$target" || exit 1; ` +
      `else git rm -r --cached -q --ignore-unmatch -- "$target" || exit 1; fi; done`,
  );
  if (restored.exitCode !== 0) {
    throw new Error(`could not restore tracked probe state: ${restored.stderr || restored.stdout}`);
  }
  const cleaned = await repo.exec(`git clean -fdx -- ${targets}`);
  if (cleaned.exitCode !== 0) {
    throw new Error(`could not remove untracked probe fixtures: ${cleaned.stderr || cleaned.stdout}`);
  }
}

// Restore before and after the body so neither prior residue nor this body's failure contaminates another row.
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

const UNEXECUTED_EXIT_CODES = new Map([
  [126, 'not executable'],
  [127, 'not found'],
]);

// A nonzero exit cannot tell a real catch from a sabotage that merely failed to parse.
export async function expectRedBecause(
  repo: any,
  command: string,
  label: string,
  reasons: readonly string[],
  options?: { timeoutMs?: number; forbidden?: readonly string[] },
): Promise<string> {
  if (reasons.length === 0 || reasons.some(reason => reason.trim().length === 0)) {
    throw new Error(`${label}: expectRedBecause was given no refusal reason, so it could not fail`);
  }
  const result = await repo.exec(capturedEnvCommand(command, label), { timeoutMs: options?.timeoutMs ?? 240000 });
  const output = `${result.stdout}\n${result.stderr}`;
  if (result.exitCode === 0) {
    throw new Error(`${label} stayed green after sabotage`);
  }
  const unexecuted = UNEXECUTED_EXIT_CODES.get(result.exitCode);
  if (unexecuted) {
    throw new Error(`${label} could not prove sabotage: command ${unexecuted} (exit ${result.exitCode})\n${output}`);
  }
  const missing = reasons.filter(reason => !output.includes(reason));
  if (missing.length > 0) {
    throw new Error(`${label} went red for the wrong reason (missing: ${missing.join(', ')})\n${output}`);
  }
  const disqualifying = (options?.forbidden ?? []).filter(marker => output.includes(marker));
  if (disqualifying.length > 0) {
    throw new Error(`${label} went red through a disqualified path (found: ${disqualifying.join(', ')})\n${output}`);
  }
  return output;
}
