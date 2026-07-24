import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

export async function run(args: readonly string[], cwd: string): Promise<string> {
  const processHandle = Bun.spawn([...args], { cwd, stdout: 'pipe', stderr: 'pipe' });
  const [stdout, stderr, code] = await Promise.all([
    new Response(processHandle.stdout).text(),
    new Response(processHandle.stderr).text(),
    processHandle.exited,
  ]);
  if (code !== 0) throw new Error(`${args.join(' ')} failed: ${stderr}`);
  return stdout;
}

export async function scratchRepository(): Promise<{ readonly root: string; readonly remote: string }> {
  const root = await mkdtemp(join(tmpdir(), 'releaser-repo-'));
  const remote = await mkdtemp(join(tmpdir(), 'releaser-remote-'));
  await run(['git', 'init', '-q', '--initial-branch=main'], root);
  await run(['git', 'init', '-q', '--bare', '--initial-branch=main'], remote);
  await run(['git', 'config', 'user.name', 'Releaser Test'], root);
  await run(['git', 'config', 'user.email', 'releaser@example.invalid'], root);
  await run(['git', 'remote', 'add', 'origin', remote], root);
  return { root, remote };
}

export async function commitAll(root: string, message: string): Promise<void> {
  await run(['git', 'add', '--all'], root);
  await run(['git', 'commit', '-q', '--no-gpg-sign', '-m', message], root);
}
