import { describe, expect, it } from 'bun:test';
import { VersionService } from '../../../src/lib/release/version-service';
import { TEST_CONFIG } from '../../helpers/fakes';

describe('version service', () => {
  const subject = new VersionService();

  it('should select the greatest reachable valid stable tag', () => {
    // Act
    const actual = subject.latestTag(['v1.8.0', 'invalid', 'v2.0.0-alpha.1', 'v1.10.0'], 'v${version}');

    // Assert
    expect(actual).toEqual({ tag: 'v1.10.0', version: { major: 1, minor: 10, patch: 0 } });
  });

  it.each([
    ['fix: repair', { major: 1, minor: 2, patch: 4 }],
    ['feat: add', { major: 1, minor: 3, patch: 0 }],
    ['feat!: replace', { major: 2, minor: 0, patch: 0 }],
  ])('should apply release precedence for %s', (message, expected) => {
    // Act
    const actual = subject.analyze(TEST_CONFIG, { major: 1, minor: 2, patch: 3 }, [{ sha: 'a', message }]);

    // Assert
    expect(actual?.version).toEqual(expected);
  });

  it('should force the first requested release to 1.0.0', () => {
    expect(subject.analyze(TEST_CONFIG, null, [{ sha: 'a', message: 'fix: repair' }])?.version).toEqual({
      major: 1,
      minor: 0,
      patch: 0,
    });
  });

  it('should make special scopes override defaults and ignore unknown history', () => {
    expect(subject.analyze(TEST_CONFIG, null, [{ sha: 'a', message: 'feat(no-release): skip' }])).toBeNull();
    expect(subject.analyze(TEST_CONFIG, null, [{ sha: 'a', message: 'unknown!: skip' }])).toBeNull();
  });

  it('should compare major, minor, and patch components and reject malformed tag formats', () => {
    expect(subject.latestTag(['v1.9.9', 'v2.0.0', 'v2.0.1'], 'v${version}')).toEqual({
      tag: 'v2.0.1',
      version: { major: 2, minor: 0, patch: 1 },
    });
    expect(subject.parseTag('v01.2.3', 'v${version}')).toBeNull();
    expect(subject.parseTag('v1.2.3', 'release')).toBeNull();
    expect(subject.format({ major: 3, minor: 2, patch: 1 })).toBe('3.2.1');
    expect(subject.formatTag('release-${version}', { major: 3, minor: 2, patch: 1 })).toBe('release-3.2.1');
    expect(
      subject.analyze(TEST_CONFIG, { major: 1, minor: 2, patch: 3 }, [
        { sha: 'a', message: 'feat!: replace everything' },
        { sha: 'b', message: 'fix: repair a detail' },
      ])?.level,
    ).toBe('major');
  });
});
