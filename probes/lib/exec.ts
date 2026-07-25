import type { ProbeExecResult, ProbeRepo } from '@cyanprint/contracts';

function commandFailure(command: string, result: ProbeExecResult): string {
  return [
    `command failed (${result.exitCode}): ${command}`,
    result.stdout.trim() ? `stdout:\n${result.stdout.trim()}` : '',
    result.stderr.trim() ? `stderr:\n${result.stderr.trim()}` : '',
  ]
    .filter(Boolean)
    .join('\n');
}

export function shellQuote(value: string): string {
  return `'${value.replaceAll("'", `'"'"'`)}'`;
}

export async function expectSuccess(repo: ProbeRepo, command: string): Promise<ProbeExecResult> {
  const result = await repo.exec(command);
  if (result.exitCode !== 0) {
    throw new Error(commandFailure(command, result));
  }
  return result;
}

export async function expectFailure(repo: ProbeRepo, command: string): Promise<ProbeExecResult> {
  const result = await repo.exec(command);
  if (result.exitCode === 0) {
    throw new Error(`command stayed green after sabotage: ${command}`);
  }
  return result;
}

export function devShellCommand(command: string, shell = 'ci'): string {
  return `nix develop --no-write-lock-file .#${shell} -c bash -lc ${shellQuote(command)}`;
}

export async function expectDevShellSuccess(repo: ProbeRepo, command: string, shell = 'ci'): Promise<ProbeExecResult> {
  return expectSuccess(repo, devShellCommand(command, shell));
}

export async function expectDevShellFailure(repo: ProbeRepo, command: string, shell = 'ci'): Promise<ProbeExecResult> {
  return expectFailure(repo, devShellCommand(command, shell));
}
