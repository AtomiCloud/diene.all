import { describe, expect, it } from 'bun:test';
import { CommitLinter } from '../../../src/lib/commits/linter';
import type { ReleaserConfig } from '../../../src/lib/config/model';
import { TEST_CONFIG } from '../../helpers/fakes';

describe('commit linter', () => {
  const subject = new CommitLinter();

  it('should accept valid scoped, unscoped, breaking, and ignored messages', () => {
    // Act / Assert
    expect(subject.lint('feat: add release', TEST_CONFIG)).toEqual([]);
    expect(subject.lint('fix: repair behavior\n\nThis body is comfortably long enough.', TEST_CONFIG)).toEqual([]);
    expect(subject.lint('feat(api)!: replace behavior', TEST_CONFIG)).toEqual([]);
    expect(subject.lint('Merge branch main', TEST_CONFIG)).toEqual([]);
  });

  it('should enforce Gitlint title/body parity rules', () => {
    // Arrange
    const input = ` WIP bad\ttitle.\nbody without blank line \t`;

    // Act
    const actual = subject.lint(input, TEST_CONFIG);

    // Assert
    expect(actual.map(item => item.rule)).toEqual(['T4', 'T3', 'T5', 'T6', 'CT1', 'B4', 'B2', 'B3']);
  });

  it('should concatenate body lines directly at the 19-versus-20 boundary', () => {
    const actual = subject.lint('feat: add release\n\n1234567890\n123456789', TEST_CONFIG);
    expect(actual.map(item => item.rule)).toEqual(['B5']);
  });

  it('should use Unicode code-point counts for title, body-line, and body-total limits', () => {
    const config: ReleaserConfig = {
      ...TEST_CONFIG,
      lint: {
        ...TEST_CONFIG.lint,
        header: { ...TEST_CONFIG.lint.header, maxLength: 7 },
        body: { ...TEST_CONFIG.lint.body, maxLineLength: 1, minLengthWhenPresent: 2 },
      },
    };

    const actual = subject.lint('feat: 😀\n\n😀', config);
    expect(actual.map(item => item.rule)).toEqual(['B5']);
  });

  it('should reject unknown types/scopes and malformed breaking trailers', () => {
    expect(subject.lint('unknown: do a thing', TEST_CONFIG)[0]?.message).toContain('unknown commit type');
    expect(subject.lint('feat(nope): do a thing', TEST_CONFIG)[0]?.message).toContain('unknown scope');
    expect(
      subject.lint('feat: do a thing\n\nBREAKING CHANGE without colon', TEST_CONFIG).map(item => item.rule),
    ).toContain('CT1');
  });

  it('should ignore Git comment lines without losing source line numbers', () => {
    // Arrange
    const input = 'feat: add release\n\n# generated comment\nshort';

    // Act
    const actual = subject.lint(input, TEST_CONFIG);

    // Assert
    expect(actual.find(item => item.rule === 'B5')?.line).toBe(4);
  });

  it('should treat a leading blank as the title and cut at the Git scissors line', () => {
    const leadingBlank = subject.lint('\nfeat: add release', TEST_CONFIG);
    expect(leadingBlank.map(item => item.rule)).toEqual(expect.arrayContaining(['T8', 'CT1', 'B4']));
    expect(leadingBlank.every(item => item.line === 1 || item.line === 2)).toBe(true);

    const scissors = subject.lint(
      'feat: add release\n\nThis body is comfortably long enough.\n# ------------------------ >8 ------------------------\ninvalid trailing content.',
      TEST_CONFIG,
    );
    expect(scissors).toEqual([]);
  });

  it('should report the remaining header, body-line, and empty-message rules', () => {
    const config: ReleaserConfig = {
      ...TEST_CONFIG,
      lint: {
        ...TEST_CONFIG.lint,
        header: { ...TEST_CONFIG.lint.header, maxLength: 10 },
        body: { ...TEST_CONFIG.lint.body, maxLineLength: 5 },
      },
    };

    expect(subject.lint('feat: a subject that is too long\nbody-too-long', config).map(item => item.rule)).toEqual([
      'T1',
      'B4',
      'B1',
    ]);
    expect(subject.lint('feat:  ', config).map(item => item.rule)).toEqual(['T2', 'CT1']);
    expect(subject.lint('# comment only', config)).toEqual([
      { line: 1, rule: 'CT1', message: 'commit message is empty' },
    ]);
  });
});
