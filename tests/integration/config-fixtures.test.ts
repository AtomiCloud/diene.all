import { describe, expect, it } from 'bun:test';
import { YamlConfigRepository } from '../../src/adapters/config/yaml-config-repository';
import { BunFileSystem } from '../../src/adapters/filesystem/bun-filesystem';
import { CommitLinter } from '../../src/lib/commits/linter';
import { ConventionsService } from '../../src/lib/release/conventions-service';
import cases from '../fixtures/lint/cases.json';

const names = ['bun-base', 'bun-cli', 'bun-consumer', 'bun-lib', 'dotnet-api', 'dotnet-base', 'dotnet-lib', 'shared'];

describe('frozen configuration fixtures', () => {
  it('should translate all eight real v1 configurations and preserve their four plugin shapes', async () => {
    // Arrange
    const subject = new YamlConfigRepository(new BunFileSystem(process.cwd()));

    // Act
    const loaded = await Promise.all(names.map(name => subject.load(`tests/fixtures/config/v1/${name}.yaml`)));

    // Assert
    expect(loaded).toHaveLength(8);
    expect(loaded.every(item => item.sourceVersion === 1)).toBe(true);
    expect(loaded[names.indexOf('bun-cli')]?.config.release.github).toBe(false);
    expect(loaded[names.indexOf('bun-cli')]?.config.release.hooks.prepare.map(hook => hook.phase)).toEqual([
      'beforeWrite',
      'afterWrite',
    ]);
    expect(loaded[names.indexOf('bun-base')]?.config.release.hooks.prepare).toHaveLength(1);
    expect(loaded[names.indexOf('dotnet-base')]?.config.release.hooks.prepare).toHaveLength(0);
    expect(loaded[names.indexOf('shared')]?.config.conventions.template).toContain('var___convention_docs___');
  });

  it('should load canonical v2 and reject unknown modules and prerelease configuration', async () => {
    // Arrange
    const subject = new YamlConfigRepository(new BunFileSystem(process.cwd()));

    // Act / Assert
    expect((await subject.load('tests/fixtures/config/v2/canonical.yaml')).sourceVersion).toBe(2);
    await expect(subject.load('tests/fixtures/config/v2/unknown-module-v1.yaml')).rejects.toThrow(
      '@semantic-release/npm',
    );
    await expect(subject.load('tests/fixtures/config/v2/invalid-prerelease.yaml')).rejects.toThrow();
  });

  it('should satisfy the lint parity and expansion case table from the canonical vocabulary', async () => {
    // Arrange
    const config = (await new YamlConfigRepository(new BunFileSystem(process.cwd())).load('atomi_release.yaml')).config;
    const subject = new CommitLinter();

    // Act / Assert
    for (const fixture of cases) {
      const diagnostics = subject.lint(fixture.message, config);
      expect(diagnostics.length === 0, fixture.name).toBe(fixture.valid);
      if ('expectedRules' in fixture && fixture.expectedRules !== undefined) {
        expect(
          diagnostics.map(item => item.rule),
          fixture.name,
        ).toEqual(fixture.expectedRules);
      }
    }
  });

  it('should render the reviewed convention golden byte-for-byte', async () => {
    // Arrange
    const config = (await new YamlConfigRepository(new BunFileSystem(process.cwd())).load('atomi_release.yaml')).config;
    const expected = await Bun.file('tests/fixtures/golden/conventions.md').text();

    // Act
    const actual = new ConventionsService().render(config);

    // Assert
    expect(actual).toBe(expected);
  });
});
