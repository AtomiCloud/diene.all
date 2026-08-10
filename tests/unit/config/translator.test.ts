import { describe, expect, it } from 'bun:test';
import { translateV1 } from '../../../src/lib/config/translator';
import { UnsupportedModuleError } from '../../../src/lib/errors';
import { HookTemplate } from '../../../src/lib/release/hook-template';

function legacy(): Record<string, unknown> {
  return {
    conventionMarkdown: { path: 'CommitConventions.md', template: 'var___convention_docs___' },
    gitlint: '.gitlint',
    branches: ['main'],
    types: [{ type: 'feat', desc: 'Features', scopes: { default: { desc: 'Feature', release: 'minor' } } }],
    specialScopes: { 'no-release': { desc: 'No release', release: false } },
    keywords: ['BREAKING CHANGE'],
    plugins: [
      { module: '@semantic-release/exec', version: '6.0.3', config: { prepareCmd: './backup.sh' } },
      { module: '@semantic-release/changelog', config: { changelogFile: 'CHANGELOG.md' } },
      {
        module: '@semantic-release/exec',
        config: { prepareCmd: './bump.sh ${nextRelease.version}', successCmd: './done.sh ${nextRelease.version}' },
      },
      {
        module: '@semantic-release/git',
        config: {
          message: 'release: ${nextRelease.version}\n\n${nextRelease.notes}\n\n[skip ci]',
          assets: ['CHANGELOG.md'],
        },
      },
      { module: '@semantic-release/github' },
    ],
  };
}

describe('v1 translator', () => {
  it('should preserve module order, hook phases, and placeholder newlines', () => {
    // Act
    const actual = translateV1(legacy());

    // Assert
    expect(actual.config.release.hooks.prepare).toEqual([
      { phase: 'beforeWrite', command: './backup.sh' },
      { phase: 'afterWrite', command: './bump.sh ${version}' },
    ]);
    expect(actual.config.release.hooks.success).toEqual(['./done.sh ${version}']);
    expect(actual.config.release.commit.message).toStartWith('release: ${version}\n\n${notes}');
    expect(actual.config.release.commit.message).not.toContain('[skip ci]');
    expect(actual.warnings).toHaveLength(1);
  });

  it('should map a missing GitHub module to false', () => {
    // Arrange
    const input = legacy();
    input.plugins = (input.plugins as Array<{ module: string }>).filter(
      plugin => plugin.module !== '@semantic-release/github',
    );

    // Act
    const actual = translateV1(input);

    // Assert
    expect(actual.config.release.github).toBe(false);
  });

  it('should canonicalize and render legacy GitHub comment placeholders', () => {
    // Arrange
    const input = legacy();
    const github = (input.plugins as Array<{ module: string; config?: Record<string, unknown> }>).find(
      plugin => plugin.module === '@semantic-release/github',
    );
    if (github === undefined) throw new Error('fixture requires its GitHub plugin');
    github.config = {
      successComment: 'Released ${nextRelease.version}: ${nextRelease.notes}',
      releasedLabels: ['released'],
    };

    // Act
    const actual = translateV1(input);
    const config = actual.config.release.github;
    if (config === false) throw new Error('translated GitHub configuration must be enabled');
    const rendered = new HookTemplate().renderText(config.successComment, '1.2.3', 'exact notes\n');

    // Assert
    expect(config.successComment).toBe('Released ${version}: ${notes}');
    expect(rendered).toBe('Released 1.2.3: exact notes');
    expect(rendered).not.toContain('nextRelease');
  });

  it('should hard-fail an unknown module and unsupported lifecycle', () => {
    // Arrange
    const unknown = legacy();
    (unknown.plugins as unknown[]).push({ module: '@semantic-release/npm' });
    const lifecycle = legacy();
    const firstPlugin = (lifecycle.plugins as Array<{ module: string; config?: Record<string, unknown> }>)[0];
    if (firstPlugin === undefined) throw new Error('fixture requires its first plugin');
    firstPlugin.config = {
      verifyConditionsCmd: './verify.sh',
    };

    // Act / Assert
    expect(() => translateV1(unknown)).toThrow(UnsupportedModuleError);
    expect(() => translateV1(unknown)).toThrow('@semantic-release/npm');
    expect(() => translateV1(lifecycle)).toThrow('verifyConditionsCmd');
  });

  it('should reject malformed Git and GitHub plugin values', () => {
    const invalidAssets = legacy();
    const git = (invalidAssets.plugins as Array<{ module: string; config?: Record<string, unknown> }>).find(
      plugin => plugin.module === '@semantic-release/git',
    );
    if (git === undefined || git.config === undefined) throw new Error('fixture requires its Git plugin');
    git.config.assets = ['CHANGELOG.md', 42];

    const invalidLabels = legacy();
    const github = (invalidLabels.plugins as Array<{ module: string; config?: Record<string, unknown> }>).find(
      plugin => plugin.module === '@semantic-release/github',
    );
    if (github === undefined) throw new Error('fixture requires its GitHub plugin');
    github.config = { releasedLabels: ['released', ''] };

    const invalidMessage = legacy();
    const invalidMessageGit = (
      invalidMessage.plugins as Array<{ module: string; config?: Record<string, unknown> }>
    ).find(plugin => plugin.module === '@semantic-release/git');
    if (invalidMessageGit === undefined || invalidMessageGit.config === undefined)
      throw new Error('fixture requires its Git plugin');
    invalidMessageGit.config.message = 42;

    expect(() => translateV1(invalidAssets)).toThrow('string[] `assets`');
    expect(() => translateV1(invalidLabels)).toThrow('releasedLabels must be a string[]');
    expect(() => translateV1(invalidMessage)).toThrow('@semantic-release/git.message must be a string');
  });

  it('should require exactly one changelog, Git, and GitHub plugin', () => {
    const missingChangelog = legacy();
    missingChangelog.plugins = (missingChangelog.plugins as Array<{ module: string }>).filter(
      plugin => plugin.module !== '@semantic-release/changelog',
    );
    const missingGit = legacy();
    missingGit.plugins = (missingGit.plugins as Array<{ module: string }>).filter(
      plugin => plugin.module !== '@semantic-release/git',
    );
    const duplicateChangelog = legacy();
    (duplicateChangelog.plugins as unknown[]).push({ module: '@semantic-release/changelog' });
    const duplicateGit = legacy();
    const git = (duplicateGit.plugins as Array<{ module: string; config?: Record<string, unknown> }>).find(
      plugin => plugin.module === '@semantic-release/git',
    );
    if (git === undefined) throw new Error('fixture requires its Git plugin');
    (duplicateGit.plugins as unknown[]).push(git);
    const duplicateGithub = legacy();
    (duplicateGithub.plugins as unknown[]).push({ module: '@semantic-release/github' });

    expect(() => translateV1(missingChangelog)).toThrow('requires an @semantic-release/changelog module');
    expect(() => translateV1(missingGit)).toThrow('requires an @semantic-release/git module');
    expect(() => translateV1(duplicateChangelog)).toThrow('duplicate @semantic-release/changelog');
    expect(() => translateV1(duplicateGit)).toThrow('duplicate @semantic-release/git');
    expect(() => translateV1(duplicateGithub)).toThrow('duplicate @semantic-release/github');
    expect(() => translateV1('not a mapping')).toThrow('invalid v1 configuration');
  });
});
