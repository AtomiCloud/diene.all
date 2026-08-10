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

export async function expectGreen(repo: any, command: string, label: string): Promise<void> {
  const result = await repo.exec(capturedEnvCommand(command, label), { timeoutMs: 240000 });
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

function shellArgument(value: string): string {
  return "'" + value.replaceAll("'", "'\\''") + "'";
}

// Restore the sandbox to HEAD and drop the probe's own fixtures. `git clean` is
// scoped to the caller's targets so a probe never removes work it does not own.
// Fixtures are made writable first: a probe that proves read-only package content
// is vendored leaves read-only trees behind, and both `git clean` and a later
// `rm -rf` fail on those unless the permission is restored.
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
  // STAGED DELETION removes the path from its output and the restore reports success while leaving
  // the deletion staged. `git ls-tree` reads HEAD, where that path remains visible.
  //
  // Classify each owned target independently: paths present in HEAD are restored from HEAD; paths
  // absent from HEAD can only be staged additions or untracked fixtures, so remove them from the
  // index and let the scoped clean below remove their worktree copies. This remains target-scoped
  // because restoring `-- .` would discard unrelated work in a shared checkout.
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

const EVIDENCE_ROOT = '.probe-evidence';
const SAFE_EVIDENCE_ID = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

/**
 * Restore `source` to `original` from a probe's `finally`, keeping the mutated
 * bytes as evidence under `.probe-evidence/<evidenceId>/` first.
 *
 * Two failure modes this exists for. A mutation probe that throws mid-assertion
 * leaves the sabotage in the sandbox, which makes every later row in that
 * sandbox suspect; and a plain restore destroys the only record of what was
 * actually mutated, so a probe that went red for the wrong reason cannot be
 * told from one that went red for the right one.
 *
 * The restore runs in this function's own `finally`, so a failure to write or
 * verify the evidence copy never leaves the sabotage in place. `.probe-evidence/`
 * is gitignored, so the copy is not itself a tree mutation.
 */
export async function preserveMutationBeforeRestore(
  repo: any,
  evidenceId: string,
  source: string,
  original: string,
): Promise<void> {
  // The id becomes a directory name and the path becomes a shell argument, so
  // both are validated before either is used. An id that escaped its directory
  // would let one probe's evidence overwrite another's, and the failure would
  // look like a wrong mutation rather than a bad id.
  if (!SAFE_EVIDENCE_ID.test(evidenceId)) {
    throw new Error(`preserveMutationBeforeRestore: '${evidenceId}' is not a usable evidence id`);
  }
  if (source.length === 0 || source.startsWith('/') || source.split('/').includes('..')) {
    throw new Error(`preserveMutationBeforeRestore: '${source}' is not a repository-relative path`);
  }

  const evidenceDir = `${EVIDENCE_ROOT}/${evidenceId}`;
  const evidence = `${evidenceDir}/${source.replaceAll('/', '__')}`;
  try {
    const copied = await repo.exec(
      `mkdir -p ${shellArgument(evidenceDir)} && cp -- ${shellArgument(source)} ${shellArgument(evidence)}`,
    );
    if (copied.exitCode !== 0) {
      throw new Error(
        `preserveMutationBeforeRestore: could not preserve ${source}: ${copied.stderr || copied.stdout}`,
      );
    }
    // Verify the copy rather than trusting the exit code: an evidence file that
    // silently holds the wrong bytes is worse than no evidence file, because it
    // is read later as proof.
    const verified = await repo.exec(`cmp -s -- ${shellArgument(source)} ${shellArgument(evidence)}`);
    if (verified.exitCode !== 0) {
      throw new Error(`preserveMutationBeforeRestore: the preserved copy of ${source} does not match the mutation`);
    }
  } finally {
    await repo.write(source, original);
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
