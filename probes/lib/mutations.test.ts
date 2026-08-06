import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { mkdir, mkdtemp, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, test } from 'bun:test';
import type { ProbeExecResult, ProbeRepo } from '@cyanprint/contracts';
import { restoreProbeState } from './helpers.ts';
import {
  breakShellGuard,
  flipAssertion,
  invalidWorkflow,
  plantSecret,
  staleHelmDocs,
  uncoverDomainFile,
  unformatFile,
} from './mutations';

class FakeRepo implements ProbeRepo {
  readonly files = new Map<string, string>();
  readonly commands: string[] = [];

  constructor(files: Record<string, string>) {
    for (const [path, content] of Object.entries(files)) {
      this.files.set(path, content);
    }
  }

  async exec(command: string): Promise<ProbeExecResult> {
    this.commands.push(command);
    return { exitCode: 0, stdout: '', stderr: '' };
  }

  async read(path: string): Promise<string> {
    const content = this.files.get(path);
    if (content === undefined) {
      throw new Error(`missing fake file: ${path}`);
    }
    return content;
  }

  async write(path: string, content: string): Promise<void> {
    this.files.set(path, content);
  }

  async remove(path: string): Promise<void> {
    this.files.delete(path);
  }

  async glob(pattern: string): Promise<string[]> {
    const suffixes = [...pattern.matchAll(/\.([A-Za-z0-9]+)(?=[,}])/g)].map(match => `.${match[1]}`);
    const simpleSuffix = pattern.match(/\*\.([A-Za-z0-9]+)$/)?.[1];
    const allowed = simpleSuffix ? [`.${simpleSuffix}`] : suffixes;
    return [...this.files.keys()].filter(path => {
      if (pattern.startsWith('.github/workflows/') && !path.startsWith('.github/workflows/')) {
        return false;
      }
      if (pattern.startsWith('scripts/') && !path.startsWith('scripts/')) {
        return false;
      }
      if (pattern.startsWith('infra/') && !path.startsWith('infra/')) {
        return false;
      }
      return allowed.length === 0 || allowed.some(suffix => path.endsWith(suffix));
    });
  }

  async patch(path: string, edit: { find: string; replace: string }): Promise<void> {
    const source = await this.read(path);
    if (!source.includes(edit.find)) {
      throw new Error(`missing patch target: ${edit.find}`);
    }
    this.files.set(path, source.replace(edit.find, edit.replace));
  }
}

describe('structural probe mutators', () => {
  test('flips a test assertion without naming a sample file', async () => {
    const repo = new FakeRepo({
      'tests/unit/domain.test.ts': 'expect(value).toBe(true);\n',
    });
    await flipAssertion(repo);
    expect(await repo.read('tests/unit/domain.test.ts')).toContain('.toBe(false)');
  });

  test('breaks a one-line shell guard', async () => {
    const repo = new FakeRepo({
      'scripts/local/secrets.sh': '[ -z "${TOKEN:-}" ] && echo missing >&2 && exit 1\n',
    });
    await breakShellGuard(repo);
    expect(await repo.read('scripts/local/secrets.sh')).toContain('exit 0');
  });

  test('creates an uncovered TypeScript domain file', async () => {
    const repo = new FakeRepo({
      'src/lib/service.ts': 'export const service = 1;\n',
    });
    const result = await uncoverDomainFile(repo);
    expect(result.path).toBe('src/lib/__probe_uncovered__.ts');
    expect(repo.files.has(result.path)).toBeTrue();
  });

  test('plants and stages a fake secret', async () => {
    const repo = new FakeRepo({});
    const result = await plantSecret(repo, { staged: true });
    expect(await repo.read(result.path)).toContain('PROBE_FAKE_GITHUB_TOKEN');
    expect(repo.commands).toEqual(["git add -- 'probe-secret.txt'"]);
  });

  test('makes helm-docs stale by adding a documented value', async () => {
    const repo = new FakeRepo({
      'infra/root_chart/values.yaml': 'service: app\n',
    });
    await staleHelmDocs(repo);
    expect(await repo.read('infra/root_chart/values.yaml')).toContain('probeHelmDocsStale');
  });

  test('creates formatter-specific violations', async () => {
    const repo = new FakeRepo({ 'nix/packages.nix': 'value = true;\n' });
    await unformatFile(repo, { formatter: 'nixfmt' });
    expect(await repo.read('nix/packages.nix')).toContain('value=true');
  });

  test('breaks workflow syntax or jobs-to-scripts wiring independently', async () => {
    const syntaxRepo = new FakeRepo({
      '.github/workflows/ci.yaml': 'jobs:\n  ci:\n',
    });
    await invalidWorkflow(syntaxRepo);
    expect(await syntaxRepo.read('.github/workflows/ci.yaml')).toContain('jobs: [');

    const wiringRepo = new FakeRepo({
      '.github/workflows/ci.yaml': 'run: ./scripts/ci/test.sh\n',
    });
    await invalidWorkflow(wiringRepo, { mode: 'missing-script' });
    expect(await wiringRepo.read('.github/workflows/ci.yaml')).toContain('__probe_missing__.sh');
  });

  test('restores only the mutation targets', async () => {
    const repo = new FakeRepo({});
    await restoreProbeState(repo, ['lib/note/note.go']);
    expect(repo.commands).toEqual([
      `for target in 'lib/note/note.go'; do if [ -e "$target" ]; then chmod -R u+w -- "$target" || exit 1; fi; done`,
      `for target in 'lib/note/note.go'; do if [ -n "$(git ls-tree -r --name-only HEAD -- "$target")" ]; then ` +
        `git restore --source=HEAD --staged --worktree -- "$target" || exit 1; ` +
        `else git rm -r --cached -q --ignore-unmatch -- "$target" || exit 1; fi; done`,
      `git clean -fdx -- 'lib/note/note.go'`,
    ]);
  });

  // The assertion above compares command STRINGS against a FakeRepo whose exec is a no-op. It
  // cannot distinguish a restore that works from one that silently does nothing, which is exactly
  // how the `git ls-files` worklist survived: a staged deletion drops the path from the index, the
  // piped `xargs -0 -r` runs zero commands, and the helper reports success. These tests run the
  // helper against a REAL git repository so a regression has to actually restore the file.
  describe('against a real repository', () => {
    async function sandbox(): Promise<{ path: string; repo: ProbeRepo; git: (c: string) => string }> {
      const path = await mkdtemp(join(tmpdir(), 'probe-restore-'));
      const run = (command: string) => execFileSync('bash', ['-c', command], { cwd: path, encoding: 'utf8' });
      run('git init -q . && git config user.email probe@test && git config user.name probe');
      await mkdir(join(path, 'lib', 'note'), { recursive: true });
      await writeFile(join(path, 'lib', 'note', 'note.go'), 'package note\n');
      run('git add -A && git commit -qm seed');
      const repo: ProbeRepo = {
        async exec(command: string): Promise<ProbeExecResult> {
          const result = spawnSync('bash', ['-c', command], { cwd: path, encoding: 'utf8' });
          return { exitCode: result.status ?? 1, stdout: result.stdout ?? '', stderr: result.stderr ?? '' };
        },
        async read(file: string) {
          return readFileSync(join(path, file), 'utf8');
        },
        async write(file: string, content: string) {
          await writeFile(join(path, file), content);
        },
      };
      return { path, repo, git: run };
    }

    test('restores a target whose deletion has been STAGED', async () => {
      const { path, repo, git } = await sandbox();
      git(`git rm -q --cached -- lib/note/note.go && rm -f -- lib/note/note.go`);
      expect(git('git status --porcelain').trim()).toBe('D  lib/note/note.go');

      await restoreProbeState(repo, ['lib/note/note.go']);

      expect(git('git status --porcelain').trim()).toBe('');
      expect(existsSync(join(path, 'lib/note/note.go'))).toBe(true);
    });

    test('restores a target whose deletion has been staged as part of a DIRECTORY', async () => {
      const { path, repo, git } = await sandbox();
      git(`git rm -q -r --cached -- lib && rm -rf -- lib`);
      expect(git('git status --porcelain').trim()).toBe('D  lib/note/note.go');

      await restoreProbeState(repo, ['lib']);

      expect(git('git status --porcelain').trim()).toBe('');
      expect(existsSync(join(path, 'lib/note/note.go'))).toBe(true);
    });

    test('drops a STAGED ADDITION under a target HEAD has never seen', async () => {
      const { path, repo, git } = await sandbox();
      await mkdir(join(path, 'fixture'), { recursive: true });
      await writeFile(join(path, 'fixture', 'planted.go'), 'package fixture\n');
      git('git add fixture/planted.go');

      await restoreProbeState(repo, ['fixture']);

      expect(git('git status --porcelain').trim()).toBe('');
      expect(existsSync(join(path, 'fixture/planted.go'))).toBe(false);
    });

    test('tolerates a target that exists nowhere', async () => {
      const { repo, git } = await sandbox();
      await restoreProbeState(repo, ['never_existed']);
      expect(git('git status --porcelain').trim()).toBe('');
    });

    test('leaves uncommitted work OUTSIDE the caller targets alone', async () => {
      const { path, repo, git } = await sandbox();
      await writeFile(join(path, 'peer.txt'), 'peer edit\n');
      git('git add peer.txt && git commit -qm peer');
      await writeFile(join(path, 'peer.txt'), 'peer edit in flight\n');
      await writeFile(join(path, 'lib', 'note', 'note.go'), 'package note // mutated\n');

      await restoreProbeState(repo, ['lib/note/note.go']);

      expect(readFileSync(join(path, 'peer.txt'), 'utf8')).toBe('peer edit in flight\n');
      expect(readFileSync(join(path, 'lib/note/note.go'), 'utf8')).toBe('package note\n');
    });
  });
});
