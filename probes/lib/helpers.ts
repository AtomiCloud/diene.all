export async function expectGreen(repo: any, command: string, label: string, timeoutMs = 240000): Promise<void> {
  const result = await repo.exec(command, { timeoutMs });
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

// Restore only the caller's tracked targets to HEAD and drop its own fixtures.
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
  const restored = await repo.exec(
    `git ls-files -z -- ${targets} | xargs -0 -r git restore --source=HEAD --staged --worktree --`,
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
