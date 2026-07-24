import { describe, expect, it } from 'bun:test';
import { translateV1 } from '../../../src/lib/config/translator';
import { MigrationService } from '../../../src/lib/migration/migration-service';
import { FakeConfigRepository, loadedConfig, MemoryFileSystem } from '../../helpers/fakes';

describe('migration service', () => {
  it('should atomically write v2 before deleting legacy files and print the checklist', async () => {
    // Arrange
    const configs = new FakeConfigRepository(loadedConfig(undefined, 1));
    const files = new MemoryFileSystem({ '.gitlint': 'legacy', '.releaserc.yaml': 'generated' });
    const subject = new MigrationService(configs, files);

    // Act
    const actual = await subject.migrate();

    // Assert
    expect(configs.written?.schemaVersion).toBe(2);
    expect(await files.exists('.gitlint')).toBe(false);
    expect(await files.exists('.releaserc.yaml')).toBe(false);
    expect(actual.output).toContain('replace Nix sg/Gitlint packages with releaser');
    expect(actual.output).toContain('remove cache-npm');
  });

  it('should be byte-idempotent for v2 while removing stale legacy files', async () => {
    // Arrange
    const configs = new FakeConfigRepository(loadedConfig());
    const files = new MemoryFileSystem({ '.gitlint': 'legacy' });
    const subject = new MigrationService(configs, files);

    // Act
    const actual = await subject.migrate();

    // Assert
    expect(configs.written).toBeNull();
    expect(actual.alreadyV2).toBe(true);
    expect(actual.output).toStartWith('already v2');
    expect(actual.output).not.toContain('normalizations:');
  });

  it('should report skip-CI normalization without consuming adjacent line breaks', async () => {
    // Arrange
    const translated = translateV1({
      conventionMarkdown: { path: 'CommitConventions.md', template: 'CONVENTION_DOCS_PLACEHOLDER' },
      branches: ['main'],
      types: [
        {
          type: 'feat',
          desc: 'Features',
          scopes: { default: { desc: 'Feature', release: 'minor' } },
        },
      ],
      plugins: [
        { module: '@semantic-release/changelog' },
        {
          module: '@semantic-release/git',
          config: {
            message: 'release: ${nextRelease.version}\n\n${nextRelease.notes}\n\n[skip ci]\n\nSigned',
            assets: ['Changelog.md'],
          },
        },
      ],
    });
    const configs = new FakeConfigRepository({
      config: translated.config,
      sourceVersion: 1,
      warnings: translated.warnings,
      legacyGitlintPath: translated.gitlintPath,
    });
    const subject = new MigrationService(configs, new MemoryFileSystem());

    // Act
    const actual = await subject.migrate();

    // Assert
    expect(configs.written?.release.commit.message).toBe('release: ${version}\n\n${notes}\n\n\n\nSigned');
    expect(actual.output).toContain('normalizations:\n- removed legacy [skip ci] token');
  });
});
