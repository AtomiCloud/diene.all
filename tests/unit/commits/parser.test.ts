import { describe, expect, it } from 'bun:test';
import { parseCommitMessage } from '../../../src/lib/commits/parser';

describe('commit parser', () => {
  it.each([
    ['feat: add release', 'feat', null, false],
    ['fix(api): repair route', 'fix', 'api', false],
    ['feat!: replace interface', 'feat', null, true],
    ['feat(api)!: replace interface', 'feat', 'api', true],
  ])('should parse %s', (message, type, scope, breaking) => {
    // Act
    const actual = parseCommitMessage(message, ['BREAKING CHANGE']);

    // Assert
    expect(actual.kind).toBe('conventional');
    if (actual.kind === 'conventional') {
      expect(actual.commit.type).toBe(type);
      expect(actual.commit.scope).toBe(scope);
      expect(actual.commit.breaking).toBe(breaking);
    }
  });

  it('should parse CRLF bodies and breaking trailers', () => {
    // Arrange
    const input = 'feat: add release\r\n\r\nA sufficiently descriptive body.\r\n\r\nBREAKING CHANGE: new contract';

    // Act
    const actual = parseCommitMessage(input, ['BREAKING CHANGE']);

    // Assert
    expect(actual.kind).toBe('conventional');
    if (actual.kind === 'conventional') {
      expect(actual.commit.breaking).toBe(true);
      expect(actual.commit.footers).toContainEqual({ token: 'BREAKING CHANGE', value: 'new contract' });
    }
  });

  it.each(['Merge branch main', 'Revert "feat: x"', 'fixup! feat: x', 'amend! feat: x', 'squash! feat: x'])(
    'should ignore %s',
    message => {
      expect(parseCommitMessage(message, []).kind).toBe('ignored');
    },
  );

  it('should mark malformed headers', () => {
    expect(parseCommitMessage('not conventional', []).kind).toBe('malformed');
  });
});
