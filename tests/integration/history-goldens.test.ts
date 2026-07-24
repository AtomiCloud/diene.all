import { afterEach, describe, expect, it } from 'bun:test';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { YamlConfigRepository } from '../../src/adapters/config/yaml-config-repository';
import { BunFileSystem } from '../../src/adapters/filesystem/bun-filesystem';
import { GitCli } from '../../src/adapters/git/git-cli';
import { NotesService } from '../../src/lib/release/notes-service';
import { VersionService } from '../../src/lib/release/version-service';
import { run } from '../helpers/scratch-repo';

const fixtures = [
  { name: 'bun-base', sha: '54bd91a', repository: 'https://github.com/AtomiCloud/diene.bun-base' },
  { name: 'bun-cli', sha: '4c01c90', repository: 'https://github.com/AtomiCloud/diene.bun-cli' },
  { name: 'bun-lib', sha: '6250148', repository: 'https://github.com/AtomiCloud/diene.bun-lib' },
  { name: 'dotnet-base', sha: 'cf94bed', repository: 'https://github.com/AtomiCloud/diene.dotnet-base' },
] as const;
const roots: string[] = [];

async function materialize(name: string, sha: string): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), 'releaser-history-'));
  roots.push(root);
  await run(['git', 'clone', '-q', `tests/fixtures/golden/${name}-history.bundle`, root], process.cwd());
  await run(['git', 'switch', '-q', '--detach', sha], root);
  return root;
}

afterEach(async () => {
  await Promise.all(roots.splice(0).map(path => rm(path, { recursive: true })));
});

describe('real-history goldens', () => {
  for (const fixture of fixtures) {
    it(`should reproduce ${fixture.name} version and notes bytes`, async () => {
      // Arrange
      const root = await materialize(fixture.name, fixture.sha);
      const config = (await new YamlConfigRepository(new BunFileSystem(root)).load('atomi_release.yaml')).config;
      const git = new GitCli(root);
      const versions = new VersionService();
      const latest = versions.latestTag(await git.reachableTags(), config.release.tagFormat);
      const commits = await git.commitsSince(latest?.tag ?? null);

      // Act
      const decision = versions.analyze(config, latest?.version ?? null, commits);
      const version = decision === null ? null : versions.format(decision.version);
      const notes =
        decision === null
          ? null
          : new NotesService().render({
              config,
              version: versions.format(decision.version),
              previousTag: latest?.tag ?? null,
              newTag: versions.formatTag(config.release.tagFormat, decision.version),
              commits,
              repositoryUrl: fixture.repository,
              date: '2026-07-22',
            });

      // Assert
      expect(`${version}\n`).toBe(await Bun.file(`tests/fixtures/golden/${fixture.name}-version.txt`).text());
      expect(notes).toBe(await Bun.file(`tests/fixtures/golden/${fixture.name}-notes.md`).text());
    });
  }

  it('should keep computation median and maximum below five seconds on the largest captured history', async () => {
    // Arrange
    const root = await materialize('bun-cli', '4c01c90');
    const config = (await new YamlConfigRepository(new BunFileSystem(root)).load('atomi_release.yaml')).config;
    const git = new GitCli(root);
    const versions = new VersionService();
    const latest = versions.latestTag(await git.reachableTags(), config.release.tagFormat);
    const commits = await git.commitsSince(latest?.tag ?? null);
    const timings: number[] = [];

    // Act
    for (let index = 0; index < 25; index += 1) {
      const start = performance.now();
      versions.analyze(config, latest?.version ?? null, commits);
      timings.push(performance.now() - start);
    }
    timings.sort((left, right) => left - right);

    // Assert
    expect(timings[Math.floor(timings.length / 2)] ?? Number.POSITIVE_INFINITY).toBeLessThan(5_000);
    expect(timings.at(-1) ?? Number.POSITIVE_INFINITY).toBeLessThan(5_000);
  });
});
