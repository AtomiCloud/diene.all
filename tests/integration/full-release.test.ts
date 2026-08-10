import { afterEach, describe, expect, it } from 'bun:test';
import { rm } from 'node:fs/promises';
import { join } from 'node:path';
import { YamlConfigRepository } from '../../src/adapters/config/yaml-config-repository';
import { BunFileSystem } from '../../src/adapters/filesystem/bun-filesystem';
import { GitCli } from '../../src/adapters/git/git-cli';
import { BunHookRunner } from '../../src/adapters/process/bun-hook-runner';
import { ConventionsService } from '../../src/lib/release/conventions-service';
import { HookTemplate } from '../../src/lib/release/hook-template';
import { NotesService } from '../../src/lib/release/notes-service';
import { ReleaseService } from '../../src/lib/release/release-service';
import { VersionService } from '../../src/lib/release/version-service';
import { FakeClock, FakeGitHub } from '../helpers/fakes';
import { commitAll, run, scratchRepository } from '../helpers/scratch-repo';

const roots: string[] = [];

afterEach(async () => {
  await Promise.all(roots.splice(0).map(path => rm(path, { recursive: true })));
});

describe('full local release', () => {
  it('should release into a scratch repository and local bare remote without package or lock drift', async () => {
    // Arrange
    const scratch = await scratchRepository();
    roots.push(scratch.root, scratch.remote);
    const config = `
schemaVersion: 2
types:
  - type: feat
    desc: Features
    section: Features
    scopes:
      default: { desc: Feature, release: minor }
conventions:
  path: CommitConventions.md
  template: "# Conventions\\n\\nCONVENTION_DOCS_PLACEHOLDER\\n"
release:
  branches: [main]
  changelog: { path: Changelog.md, title: "# Changelog" }
  commit:
    message: "release: \${version}\\n\\n\${notes}"
    assets: [Changelog.md, CommitConventions.md]
  github: false
`;
    await Bun.write(join(scratch.root, 'atomi_release.yaml'), config);
    await Bun.write(join(scratch.root, 'Changelog.md'), '# Changelog\n');
    await Bun.write(join(scratch.root, 'CommitConventions.md'), '# old\n');
    await Bun.write(join(scratch.root, 'package.json'), '{"name":"fixture","version":"1.0.0"}\n');
    await Bun.write(join(scratch.root, 'bun.lock'), 'locked\n');
    await commitAll(scratch.root, 'feat: add local release');
    await run(['git', 'push', '-q', '-u', 'origin', 'main'], scratch.root);
    const packageBefore = await Bun.file(join(scratch.root, 'package.json')).text();
    const lockBefore = await Bun.file(join(scratch.root, 'bun.lock')).text();
    const files = new BunFileSystem(scratch.root);
    const subject = new ReleaseService(
      new YamlConfigRepository(files),
      files,
      new GitCli(scratch.root),
      new BunHookRunner(scratch.root, process.env),
      new FakeGitHub(),
      new VersionService(),
      new NotesService(),
      new ConventionsService(),
      new HookTemplate(),
      new FakeClock(),
    );

    // Act
    const actual = await subject.release();

    // Assert
    expect(actual?.version).toBe('1.0.0');
    expect(await Bun.file(join(scratch.root, 'package.json')).text()).toBe(packageBefore);
    expect(await Bun.file(join(scratch.root, 'bun.lock')).text()).toBe(lockBefore);
    expect((await run(['git', 'status', '--porcelain'], scratch.root)).trim()).toBe('');
    expect((await run(['git', 'tag', '--list'], scratch.remote)).trim()).toBe('v1.0.0');
    expect(await run(['git', 'log', '-1', '--format=%s'], scratch.remote)).toBe('release: 1.0.0\n');
    expect(await run(['git', 'show', 'main:Changelog.md'], scratch.remote)).toContain('## 1.0.0');
  });
});
