// Opt-in budget: a starved container-backed row surfaces as an unexplained broken verdict.
export async function expectGreen(
  repo: any,
  command: string,
  label: string,
  options?: { timeoutMs?: number },
): Promise<void> {
  const result = await repo.exec(command, { timeoutMs: options?.timeoutMs ?? 240000 });
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

// A nonzero exit cannot tell a real catch from a sabotage that merely failed to parse.
export async function expectRedBecause(
  repo: any,
  command: string,
  label: string,
  reasons: readonly string[],
  options?: { timeoutMs?: number; forbidden?: readonly string[] },
): Promise<string> {
  if (reasons.length === 0) {
    throw new Error(`${label}: expectRedBecause was given no refusal reason, so it could not fail`);
  }
  const result = await repo.exec(command, { timeoutMs: options?.timeoutMs ?? 240000 });
  const output = `${result.stdout}\n${result.stderr}`;
  if (result.exitCode === 0) {
    throw new Error(`${label} stayed green after sabotage`);
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
