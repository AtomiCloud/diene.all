import { HookError } from '../../lib/errors';
import type { IHookRunner } from '../../lib/release/ports';

function redactSecrets(value: string, env: Readonly<Record<string, string | undefined>>): string {
  return Object.entries(env)
    .filter(([key, secret]) => /TOKEN|SECRET|PASSWORD|KEY/i.test(key) && secret !== undefined && secret.length > 0)
    .reduce((current, [, secret]) => current.replaceAll(secret as string, '[redacted]'), value);
}

export class BunHookRunner implements IHookRunner {
  constructor(
    private readonly cwd: string,
    private readonly env: Readonly<Record<string, string | undefined>>,
  ) {}

  async run(command: string): Promise<void> {
    const processHandle = Bun.spawn(['bash', '-c', command], {
      cwd: this.cwd,
      env: { ...this.env },
      stdout: 'pipe',
      stderr: 'pipe',
    });
    const [stdout, stderr, code] = await Promise.all([
      new Response(processHandle.stdout).text(),
      new Response(processHandle.stderr).text(),
      processHandle.exited,
    ]);
    if (code !== 0) {
      const detail = redactSecrets(stderr.trim() || stdout.trim() || `exit ${code}`, this.env);
      throw new HookError(`hook exited ${code}: ${detail}`);
    }
  }
}
