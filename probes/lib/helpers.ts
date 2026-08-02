export async function expectGreen(repo: any, command: string, label: string, timeoutMs = 240000): Promise<void> {
  const result = await repo.exec(command, { timeoutMs });
  if (result.exitCode !== 0) {
    throw new Error(`${label} failed on the healthy repo: ${result.stderr || result.stdout}`);
  }
}

export async function expectRed(
  repo: any,
  command: string,
  label: string,
  timeoutMs = 240000,
  expectedOutput?: string | RegExp,
): Promise<void> {
  const result = await repo.exec(command, { timeoutMs });
  if (result.exitCode === 0) {
    throw new Error(`${label} stayed green after sabotage`);
  }
  if (expectedOutput !== undefined) {
    const output = `${result.stdout}\n${result.stderr}`;
    const matched = typeof expectedOutput === 'string' ? output.includes(expectedOutput) : expectedOutput.test(output);
    if (!matched) {
      throw new Error(`${label} failed for the wrong reason after sabotage: ${output}`);
    }
  }
}
