import type { ProbeExecResult, ProbeRepo } from "@cyanprint/contracts";

const MAX_FAILURE_OUTPUT = 4_000;

function safeFailureOutput(output: string): string {
  const redacted = output
    .replace(/gh[pousr]_[A-Za-z0-9_]+/g, "[REDACTED_GITHUB_TOKEN]")
    .replace(/\b(?:token|secret|password)=\S+/gi, "[REDACTED_SECRET]");
  return redacted.length > MAX_FAILURE_OUTPUT
    ? `${redacted.slice(0, MAX_FAILURE_OUTPUT)}\n…[truncated]`
    : redacted;
}

function commandFailure(command: string, result: ProbeExecResult): string {
  return [
    `command failed (${result.exitCode}): ${command}`,
    result.stdout.trim()
      ? `stdout:\n${safeFailureOutput(result.stdout.trim())}`
      : "",
    result.stderr.trim()
      ? `stderr:\n${safeFailureOutput(result.stderr.trim())}`
      : "",
  ]
    .filter(Boolean)
    .join("\n");
}

export function shellQuote(value: string): string {
  return `'${value.replaceAll("'", `'"'"'`)}'`;
}

export async function expectSuccess(
  repo: ProbeRepo,
  command: string,
): Promise<ProbeExecResult> {
  const result = await repo.exec(command);
  if (result.exitCode !== 0) {
    throw new Error(commandFailure(command, result));
  }
  return result;
}

export async function expectFailure(
  repo: ProbeRepo,
  command: string,
): Promise<ProbeExecResult> {
  const result = await repo.exec(command);
  if (result.exitCode === 0) {
    throw new Error(`command stayed green after sabotage: ${command}`);
  }
  return result;
}

export function devShellCommand(command: string, shell = "ci"): string {
  return `nix develop --no-write-lock-file .#${shell} -c bash -lc ${shellQuote(command)}`;
}

export async function expectDevShellSuccess(
  repo: ProbeRepo,
  command: string,
  shell = "ci",
): Promise<ProbeExecResult> {
  return expectSuccess(repo, devShellCommand(command, shell));
}

export async function expectDevShellFailure(
  repo: ProbeRepo,
  command: string,
  shell = "ci",
): Promise<ProbeExecResult> {
  return expectFailure(repo, devShellCommand(command, shell));
}
