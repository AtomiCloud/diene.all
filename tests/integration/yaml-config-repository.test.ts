import { afterEach, describe, expect, it } from 'bun:test';
import { mkdtemp, open, rm, stat } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { BunFileSystem } from '../../src/adapters/filesystem/bun-filesystem';
import { YamlConfigRepository } from '../../src/adapters/config/yaml-config-repository';

const roots: string[] = [];

async function root(): Promise<string> {
  const value = await mkdtemp(join(tmpdir(), 'releaser-yaml-'));
  roots.push(value);
  return value;
}

afterEach(async () => {
  await Promise.all(roots.splice(0).map(path => rm(path, { recursive: true })));
});

describe('YAML config repository', () => {
  it('should read v1 and atomically serialize canonical v2 with the existing mode', async () => {
    // Arrange
    const cwd = await root();
    const path = join(cwd, 'atomi_release.yaml');
    const handle = await open(path, 'w', 0o640);
    await handle.writeFile(`
conventionMarkdown: { path: CommitConventions.md, template: CONVENTION_DOCS_PLACEHOLDER }
branches: [main]
types:
  - type: feat
    desc: Features
    scopes:
      default: { desc: Feature, release: minor }
plugins:
  - module: '@semantic-release/changelog'
  - module: '@semantic-release/git'
    config:
      message: "release: \${nextRelease.version}\\n\\n\${nextRelease.notes}"
      assets: [Changelog.md]
`);
    await handle.close();
    const files = new BunFileSystem(cwd);
    const subject = new YamlConfigRepository(files);

    // Act
    const loaded = await subject.load('atomi_release.yaml');
    await subject.writeCanonical('atomi_release.yaml', loaded.config);

    // Assert
    expect(loaded.sourceVersion).toBe(1);
    expect((await subject.load('atomi_release.yaml')).sourceVersion).toBe(2);
    expect((await stat(path)).mode & 0o777).toBe(0o640);
    expect(await files.readText('atomi_release.yaml')).toContain('schemaVersion: 2');
  });

  it('should report invalid YAML with the source path', async () => {
    // Arrange
    const cwd = await root();
    await Bun.write(join(cwd, 'broken.yaml'), 'release: [');
    const subject = new YamlConfigRepository(new BunFileSystem(cwd));

    // Act / Assert
    await expect(subject.load('broken.yaml')).rejects.toThrow('broken.yaml');
  });
});
