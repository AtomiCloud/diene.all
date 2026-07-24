import { describe, expect, it } from 'bun:test';
import { detectSchemaVersion, parseCanonicalV2 } from '../../../src/lib/config/schema';
import { ConfigError } from '../../../src/lib/errors';

function minimal(): Record<string, unknown> {
  return {
    schemaVersion: 2,
    types: [{ type: 'feat', desc: 'Features', scopes: { default: { desc: 'Feature', release: 'minor' } } }],
    conventions: { path: 'CommitConventions.md', template: 'CONVENTION_DOCS_PLACEHOLDER' },
    release: {
      branches: ['main'],
      changelog: { path: 'Changelog.md' },
      commit: { message: 'release: ${version}\n\n${notes}', assets: ['Changelog.md'] },
    },
  };
}

describe('canonical v2 schema', () => {
  it('should apply nested defaults', () => {
    // Arrange / Act
    const actual = parseCanonicalV2(minimal());

    // Assert
    expect(actual.lint.header.maxLength).toBe(72);
    expect(actual.lint.body.maxLineLength).toBe(80);
    expect(actual.release.tagFormat).toBe('v${version}');
    expect(actual.release.github).toBe(false);
  });

  it('should reject unknown nested keys with a dotted path', () => {
    // Arrange
    const input = minimal();
    (input.release as Record<string, unknown>).channel = 'next';

    // Act / Assert
    expect(() => parseCanonicalV2(input)).toThrow(ConfigError);
    expect(() => parseCanonicalV2(input)).toThrow('release: Unrecognized key');
  });

  it('should reject duplicate types and skip-CI release messages', () => {
    // Arrange
    const duplicate = minimal();
    duplicate.types = [...(duplicate.types as unknown[]), ...(duplicate.types as unknown[])];
    const skip = minimal();
    ((skip.release as Record<string, unknown>).commit as Record<string, unknown>).message =
      'release: ${version} [skip ci]';

    // Act / Assert
    expect(() => parseCanonicalV2(duplicate)).toThrow('type names must be unique');
    expect(() => parseCanonicalV2(skip)).toThrow('skip-CI');
  });

  it('should reject prerelease branch objects and invalid tag formats', () => {
    // Arrange
    const branch = minimal();
    (branch.release as Record<string, unknown>).branches = [{ name: 'main', prerelease: true }];
    const tag = minimal();
    (tag.release as Record<string, unknown>).tagFormat = 'release';

    // Act / Assert
    expect(() => parseCanonicalV2(branch)).toThrow(ConfigError);
    expect(() => parseCanonicalV2(tag)).toThrow('exactly one ${version}');
  });

  it('should reject duplicate branches, assets, and keywords together', () => {
    const input = minimal();
    input.keywords = ['BREAKING CHANGE', 'BREAKING CHANGE'];
    const release = input.release as Record<string, unknown>;
    release.branches = ['main', 'main'];
    const commit = release.commit as Record<string, unknown>;
    commit.assets = ['Changelog.md', 'Changelog.md'];

    expect(() => parseCanonicalV2(input)).toThrow('branches must be unique');
    expect(() => parseCanonicalV2(input)).toThrow('assets must be unique');
    expect(() => parseCanonicalV2(input)).toThrow('keywords must be unique');
  });

  it('should detect canonical and legacy documents and explain every invalid root shape', () => {
    expect(detectSchemaVersion(minimal())).toBe(2);
    expect(detectSchemaVersion({ branches: ['main'] })).toBe(1);
    expect(detectSchemaVersion({ plugins: [] })).toBe(1);
    expect(() => detectSchemaVersion(null)).toThrow('configuration must be a mapping');
    expect(() => detectSchemaVersion([])).toThrow('configuration must be a mapping');
    expect(() => detectSchemaVersion({ schemaVersion: 3 })).toThrow('unsupported schemaVersion: 3');
    expect(() => detectSchemaVersion({})).toThrow('unrecognized configuration');
  });
});
