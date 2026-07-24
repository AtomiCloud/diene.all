function withIsolatedGolangciCache(command: string): string {
  return `GOLANGCI_LINT_CACHE="$PWD/.git/cyanprint-golangci-cache-$$" ${command}`;
}

export async function expectGreen(repo: any, command: string, label: string): Promise<void> {
  const isolatedCommand = withIsolatedGolangciCache(command);
  const result = await repo.exec(isolatedCommand, { timeoutMs: 240000 });
  if (result.exitCode !== 0) {
    const stdout = result.stdout.trim() || '<empty>';
    const stderr = result.stderr.trim() || '<empty>';
    throw new Error(
      [
        `${label} failed on the healthy repo`,
        `command failed (${result.exitCode}): ${command}`,
        `stdout:\n${stdout}`,
        `stderr:\n${stderr}`,
      ].join('\n'),
    );
  }
}

export async function expectRed(repo: any, command: string, label: string): Promise<void> {
  const result = await repo.exec(withIsolatedGolangciCache(command), { timeoutMs: 240000 });
  if (result.exitCode === 0) {
    throw new Error(`${label} stayed green after sabotage`);
  }
}
