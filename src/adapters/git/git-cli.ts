import { open, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { RawCommit } from '../../lib/commits/model';
import { GitError } from '../../lib/errors';
import type { IGit } from '../../lib/release/ports';

interface GitResult {
  readonly stdout: string;
  readonly stderr: string;
  readonly code: number;
}

function redact(value: string, token: string | undefined): string {
  const withoutCredentials = value.replace(/(https?:\/\/)[^/@\s]+@/g, '$1[redacted]@');
  return token === undefined || token.length === 0
    ? withoutCredentials
    : withoutCredentials.replaceAll(token, '[redacted]');
}

async function runGit(
  cwd: string,
  args: readonly string[],
  env: Readonly<Record<string, string>> = {},
  allowFailure = false,
  token?: string,
): Promise<GitResult> {
  const processHandle = Bun.spawn(['git', ...args], {
    cwd,
    env: { ...process.env, ...env },
    stdout: 'pipe',
    stderr: 'pipe',
  });
  const [stdout, stderr, code] = await Promise.all([
    new Response(processHandle.stdout).text(),
    new Response(processHandle.stderr).text(),
    processHandle.exited,
  ]);
  if (code !== 0 && !allowFailure) {
    const detail = redact(stderr.trim() || stdout.trim() || `exit ${code}`, token);
    throw new GitError(`git ${args[0] ?? 'command'} failed: ${detail}`);
  }
  return { stdout, stderr, code };
}

function httpRemote(remote: string): URL | null {
  try {
    const parsed = new URL(remote.trim());
    return parsed.protocol === 'https:' || parsed.protocol === 'http:' ? parsed : null;
  } catch {
    return null;
  }
}

function githubSlug(remote: string): string | null {
  const parsed = httpRemote(remote);
  if (parsed !== null && parsed.hostname.toLowerCase() === 'github.com') {
    const path = parsed.pathname.replace(/^\/+|\/+$/g, '').replace(/\.git$/i, '');
    return /^[^/\s]+\/[^/\s]+$/.test(path) ? path : null;
  }
  const match = /^(?:git@github\.com:|ssh:\/\/git@github\.com\/)([^/\s]+\/[^/\s]+?)(?:\.git)?$/i.exec(remote.trim());
  return match?.[1] ?? null;
}

function publicRepositoryUrl(remote: string): string | null {
  const slug = githubSlug(remote);
  if (slug !== null) return `https://github.com/${slug}`;
  const parsed = httpRemote(remote);
  if (parsed === null) return null;
  const path = parsed.pathname.replace(/\.git$/i, '').replace(/\/+$/, '');
  return `${parsed.protocol}//${parsed.host}${path}`;
}

function isGitHubHttps(remote: string): { readonly hasUserInfo: boolean } | null {
  const parsed = httpRemote(remote);
  if (parsed === null || parsed.protocol !== 'https:' || parsed.hostname.toLowerCase() !== 'github.com') return null;
  return { hasUserInfo: parsed.username.length > 0 || parsed.password.length > 0 };
}

function parseLog(output: string): RawCommit[] {
  return output
    .split('\x1e')
    .map(record => record.replace(/^\n/, ''))
    .filter(record => record.includes('\x1f'))
    .map(record => {
      const separator = record.indexOf('\x1f');
      return {
        sha: record.slice(0, separator).trim(),
        message: record.slice(separator + 1).replace(/\n$/, ''),
      };
    });
}

function parseStatus(output: string): string[] {
  const records = output.split('\0');
  const paths: string[] = [];
  for (let index = 0; index < records.length; index += 1) {
    const record = records[index];
    if (record === undefined || record.length < 4) continue;
    const status = record.slice(0, 2);
    paths.push(record.slice(3));
    if (status.includes('R') || status.includes('C')) {
      const source = records[index + 1];
      if (source !== undefined && source.length > 0) paths.push(source);
      index += 1;
    }
  }
  return [...new Set(paths)].sort();
}

async function createAskPass(): Promise<string> {
  const path = join(tmpdir(), `releaser-askpass-${process.pid}-${crypto.randomUUID()}`);
  const handle = await open(path, 'wx', 0o700);
  await handle.writeFile(
    '#!/usr/bin/env bash\ncase "$1" in\n  *Username*) printf "%s\\n" "x-access-token" ;;\n  *) printf "%s\\n" "$GITHUB_TOKEN" ;;\nesac\n',
    'utf8',
  );
  await handle.sync();
  await handle.close();
  return path;
}

export class GitCli implements IGit {
  constructor(
    private readonly cwd: string,
    private readonly token?: string,
  ) {}

  async currentBranch(): Promise<string> {
    return (await runGit(this.cwd, ['branch', '--show-current'])).stdout.trim();
  }

  async isClean(): Promise<boolean> {
    return (await runGit(this.cwd, ['status', '--porcelain=v1', '--untracked-files=all'])).stdout.length === 0;
  }

  async reachableTags(): Promise<readonly string[]> {
    return (await runGit(this.cwd, ['tag', '--merged', 'HEAD', '--list'])).stdout.split('\n').filter(Boolean);
  }

  async commitsSince(tag: string | null): Promise<readonly RawCommit[]> {
    const range = tag === null ? 'HEAD' : `${tag}..HEAD`;
    const result = await runGit(this.cwd, ['log', '--format=%H%x1f%B%x1e', range]);
    return parseLog(result.stdout);
  }

  async repositoryUrl(): Promise<string | null> {
    const result = await runGit(this.cwd, ['remote', 'get-url', 'origin'], {}, true);
    return result.code === 0 ? publicRepositoryUrl(result.stdout.trim()) : null;
  }

  async githubRepository(): Promise<string | null> {
    const result = await runGit(this.cwd, ['remote', 'get-url', 'origin'], {}, true);
    return result.code === 0 ? githubSlug(result.stdout.trim()) : null;
  }

  async validateTag(tag: string): Promise<void> {
    await runGit(this.cwd, ['check-ref-format', `refs/tags/${tag}`]);
  }

  async changedFiles(): Promise<readonly string[]> {
    const result = await runGit(this.cwd, ['status', '--porcelain=v1', '-z', '--untracked-files=all']);
    return parseStatus(result.stdout);
  }

  async stage(paths: readonly string[]): Promise<void> {
    await runGit(this.cwd, ['add', '--all', '--', ...paths]);
  }

  async commit(message: string): Promise<void> {
    await runGit(this.cwd, ['commit', '--no-gpg-sign', '--cleanup=verbatim', '-m', message]);
  }

  async createTag(tag: string): Promise<void> {
    await runGit(this.cwd, ['tag', '--', tag]);
  }

  async push(branch: string, tag: string): Promise<void> {
    const remote = (await runGit(this.cwd, ['remote', 'get-url', 'origin'])).stdout.trim();
    const githubHttps = isGitHubHttps(remote);
    if (githubHttps === null) {
      await runGit(this.cwd, ['push', '--atomic', 'origin', `HEAD:${branch}`, `refs/tags/${tag}`]);
      return;
    }
    if (githubHttps.hasUserInfo) {
      throw new GitError('GitHub HTTPS origin must not contain embedded credentials; use GITHUB_TOKEN');
    }
    if (this.token === undefined || this.token.trim().length === 0) {
      throw new GitError('GITHUB_TOKEN is required to push to a GitHub HTTPS origin');
    }
    const askPass = await createAskPass();
    try {
      await runGit(
        this.cwd,
        ['push', '--atomic', 'origin', `HEAD:${branch}`, `refs/tags/${tag}`],
        { GIT_ASKPASS: askPass, GIT_TERMINAL_PROMPT: '0', GITHUB_TOKEN: this.token },
        false,
        this.token,
      );
    } finally {
      await rm(askPass);
    }
  }
}
