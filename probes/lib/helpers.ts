export async function expectGreen(repo: any, command: string, label: string): Promise<void> {
  const result = await repo.exec(command, { timeoutMs: 240000 });
  if (result.exitCode !== 0) {
    // A control can fail with BOTH streams empty (killed by signal, OOM, or a
    // silent non-zero exit). `stderr || stdout` then interpolates the empty
    // string and the row records a label with no reason, which is
    // indistinguishable from a real gate defect. Never let the reason be empty.
    const detail =
      result.stderr ||
      result.stdout ||
      `no output captured (exit ${result.exitCode}${result.signal ? `, signal ${result.signal}` : ''})`;
    throw new Error(`${label} failed on the healthy repo: ${detail}`);
  }
}

export async function expectRed(repo: any, command: string, label: string): Promise<void> {
  const result = await repo.exec(command, { timeoutMs: 240000 });
  if (result.exitCode === 0) {
    throw new Error(`${label} stayed green after sabotage`);
  }
  // A non-zero exit is NOT by itself evidence that the sabotage was detected.
  // A control killed by contention, OOM, or a missing binary also exits
  // non-zero, and the row is then recorded as `caught` on the strength of a
  // failure that has nothing to do with the mutation. Record what the command
  // actually said so a vacuous catch can be told from a real one.
  if (!result.stderr && !result.stdout) {
    throw new Error(
      `${label} exited ${result.exitCode}${result.signal ? ` (signal ${result.signal})` : ''} after sabotage but produced NO output — cannot distinguish detection from environmental failure`,
    );
  }
}
