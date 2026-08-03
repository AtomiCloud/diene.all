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
  const result = await repo.exec(command, { timeoutMs: options?.timeoutMs ?? 240000 });
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
