import type { ProbeExecResult, ProbeRepo } from '@cyanprint/contracts';
import { capturedEnvCommand } from './helpers';

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

export async function expectFailure(
  repo: ProbeRepo,
  command: string,
  reasons: readonly string[],
): Promise<ProbeExecResult> {
  if (reasons.length === 0 || reasons.some(reason => reason.trim().length === 0)) {
    throw new Error(`command failure expectation has no declared reason: ${command}`);
  }
  const result = await repo.exec(command);
  if (result.exitCode === 0) {
    throw new Error(`command stayed green after sabotage: ${command}`);
  }
  if (result.exitCode === 126 || result.exitCode === 127) {
    throw new Error(`command did not execute while checking sabotage (exit ${result.exitCode}): ${command}`);
  }
  const output = `${result.stdout}\n${result.stderr}`;
  const missing = reasons.filter(reason => !output.includes(reason));
  if (missing.length > 0) {
    throw new Error(`command went red for the wrong reason (missing: ${missing.join(', ')}): ${command}\n${output}`);
  }
  return result;
}

export function devShellCommand(command: string, shell = 'ci'): string {
  return capturedEnvCommand(`nix develop --no-write-lock-file .#${shell} -c bash -lc ${shellQuote(command)}`);
}

export async function expectDevShellSuccess(repo: ProbeRepo, command: string, shell = 'ci'): Promise<ProbeExecResult> {
  return expectSuccess(repo, devShellCommand(command, shell));
}

export async function expectDevShellFailure(
  repo: ProbeRepo,
  command: string,
  reasons: readonly string[],
  shell = 'ci',
): Promise<ProbeExecResult> {
  return expectFailure(repo, devShellCommand(command, shell), reasons);
}
