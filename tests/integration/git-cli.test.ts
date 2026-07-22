import { afterEach, describe, expect, it } from 'bun:test';
import { mkdir, open, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { GitCli } from '../../src/adapters/git/git-cli';
import { commitAll, run, scratchRepository } from '../helpers/scratch-repo';

const roots: string[] = [];

afterEach(async () => {
  await Promise.all(roots.splice(0).map(path => rm(path, { recursive: true })));
});

describe('Git CLI adapter', () => {
  it('should read history, stage exact assets, commit, tag, and atomically push to a bare remote', async () => {
    // Arrange
    const scratch = await scratchRepository();
    roots.push(scratch.root, scratch.remote);
    await Bun.write(join(scratch.root, 'Changelog.md'), '# Changelog\n');
    await commitAll(scratch.root, 'feat: initial release');
    const subject = new GitCli(scratch.root);

    // Act
    const commits = await subject.commitsSince(null);
    await Bun.write(join(scratch.root, 'Changelog.md'), '# Changelog\n\n## 1.0.0\n');
    expect(await subject.changedFiles()).toEqual(['Changelog.md']);
    await subject.stage(['Changelog.md']);
    await subject.commit('release: 1.0.0\n\nnotes');
    await subject.createTag('v1.0.0');
    await subject.push('main', 'v1.0.0');

    // Assert
    expect(commits[0]?.message).toContain('feat: initial release');
    expect(await subject.isClean()).toBe(true);
    expect(await run(['git', 'show', 'refs/heads/main:Changelog.md'], scratch.remote)).toContain('## 1.0.0');
    expect((await run(['git', 'tag', '--list'], scratch.remote)).trim()).toBe('v1.0.0');
    expect((await run(['git', 'log', '-1', '--format=%B'], scratch.root)).trimEnd()).toBe('release: 1.0.0\n\nnotes');
  });

  it('should normalize GitHub HTTPS and SSH origin identities', async () => {
    // Arrange
    const scratch = await scratchRepository();
    roots.push(scratch.root, scratch.remote);
    await run(['git', 'remote', 'set-url', 'origin', 'git@github.com:AtomiCloud/example.git'], scratch.root);
    const subject = new GitCli(scratch.root);

    // Act / Assert
    expect(await subject.repositoryUrl()).toBe('https://github.com/AtomiCloud/example');
    expect(await subject.githubRepository()).toBe('AtomiCloud/example');
  });

  it('should report both source and destination for a staged rename', async () => {
    // Arrange
    const scratch = await scratchRepository();
    roots.push(scratch.root, scratch.remote);
    await Bun.write(join(scratch.root, 'outside.txt'), 'outside\n');
    await commitAll(scratch.root, 'feat: add rename source');
    await run(['git', 'mv', 'outside.txt', 'allowed.txt'], scratch.root);

    // Act
    const actual = await new GitCli(scratch.root).changedFiles();

    // Assert
    expect(actual).toEqual(['allowed.txt', 'outside.txt']);
  });

  it('should validate tags with Git ref semantics', async () => {
    // Arrange
    const scratch = await scratchRepository();
    roots.push(scratch.root, scratch.remote);
    const subject = new GitCli(scratch.root);

    // Act / Assert
    await expect(subject.validateTag('v1.0.0')).resolves.toBeUndefined();
    for (const tag of ['bad..1.0.0', 'bad tag', 'bad@{tag}', 'component.lock']) {
      await expect(subject.validateTag(tag)).rejects.toThrow('check-ref-format');
    }
  });

  it('should remove remote credentials from identity and reject credentialed GitHub push', async () => {
    // Arrange
    const scratch = await scratchRepository();
    roots.push(scratch.root, scratch.remote);
    const sentinel = 'sentinel-secret';
    await run(
      ['git', 'remote', 'set-url', 'origin', `https://sentinel-user:${sentinel}@GitHub.com/AtomiCloud/example.git`],
      scratch.root,
    );
    const subject = new GitCli(scratch.root, 'askpass-token');

    // Act
    const repositoryUrl = await subject.repositoryUrl();
    const githubRepository = await subject.githubRepository();
    let failure = '';
    try {
      await subject.push('main', 'v1.0.0');
    } catch (error) {
      failure = String(error);
    }

    // Assert
    expect(repositoryUrl).toBe('https://github.com/AtomiCloud/example');
    expect(githubRepository).toBe('AtomiCloud/example');
    expect(repositoryUrl).not.toContain(sentinel);
    expect(failure).toContain('must not contain embedded credentials');
    expect(failure).not.toContain(sentinel);

    await run(
      ['git', 'remote', 'set-url', 'origin', `https://sentinel-user:${sentinel}@example.com/org/repo.git`],
      scratch.root,
    );
    expect(await subject.repositoryUrl()).toBe('https://example.com/org/repo');
  });

  it('should transport a GitHub token through a temporary askpass helper and remove it', async () => {
    const scratch = await scratchRepository();
    roots.push(scratch.root, scratch.remote);
    const bin = join(scratch.root, 'fake-bin');
    const marker = join(scratch.root, 'push.json');
    await mkdir(bin);
    const fakeGit = join(bin, 'git');
    const handle = await open(fakeGit, 'wx', 0o700);
    await handle.writeFile(
      `#!/usr/bin/env bun
const args = Bun.argv.slice(2);
if (args[0] === 'remote') {
  process.stdout.write('https://github.com/AtomiCloud/example.git\\n');
  process.exit(0);
}
if (args[0] === 'push') {
  const askpass = process.env.GIT_ASKPASS ?? '';
  const password = Bun.spawnSync([askpass, 'Password'], { env: process.env }).stdout.toString().trim();
  await Bun.write(${JSON.stringify(marker)}, JSON.stringify({ args, askpass, password, terminal: process.env.GIT_TERMINAL_PROMPT }));
  process.exit(0);
}
process.exit(1);
`,
      'utf8',
    );
    await handle.close();
    const previousPath = process.env.PATH;
    process.env.PATH = `${bin}:${previousPath ?? ''}`;

    try {
      await new GitCli(scratch.root, 'sentinel-token').push('main', 'v1.0.0');
    } finally {
      process.env.PATH = previousPath;
    }

    const recorded = (await Bun.file(marker).json()) as {
      readonly args: readonly string[];
      readonly askpass: string;
      readonly password: string;
      readonly terminal: string;
    };
    expect(recorded.args).toEqual(['push', '--atomic', 'origin', 'HEAD:main', 'refs/tags/v1.0.0']);
    expect(recorded.password).toBe('sentinel-token');
    expect(recorded.terminal).toBe('0');
    expect(await Bun.file(recorded.askpass).exists()).toBe(false);
  });
});
