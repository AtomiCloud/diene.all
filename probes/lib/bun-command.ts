const timeoutMs = 600_000;

export async function expectBunGreen(repo: any, command: string, label: string): Promise<void> {
  const result = await repo.exec(command, { timeoutMs });
  if (result.exitCode !== 0) {
    throw new Error(`${label} failed on the healthy repo: ${result.stderr || result.stdout}`);
  }
}

export async function expectBunRed(repo: any, command: string, label: string): Promise<void> {
  const result = await repo.exec(command, { timeoutMs });
  if (result.exitCode === 0) {
    throw new Error(`${label} stayed green after sabotage`);
  }
}
