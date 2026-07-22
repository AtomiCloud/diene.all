import type { ReleaserConfig } from '../config/model';
import type { LintDiagnostic } from './model';
import { classifyIgnored, normalizeCommitMessage, parseCommitMessage } from './parser';

interface NumberedLine {
  readonly number: number;
  readonly text: string;
}

const SCISSORS = '# ------------------------ >8 ------------------------';

function contentLines(message: string): NumberedLine[] {
  const numbered = normalizeCommitMessage(message)
    .split('\n')
    .map((text, index) => ({ number: index + 1, text }));
  const scissors = numbered.findIndex(line => line.text.trimEnd() === SCISSORS);
  return (scissors === -1 ? numbered : numbered.slice(0, scissors)).filter(line => !line.text.startsWith('#'));
}

function diagnostic(line: number, rule: string, message: string): LintDiagnostic {
  return { line, rule, message };
}

function codePointLength(value: string): number {
  return Array.from(value).length;
}

export class CommitLinter {
  lint(message: string, config: ReleaserConfig): readonly LintDiagnostic[] {
    const lines = contentLines(message);
    const title = lines[0];
    if (title === undefined) return [diagnostic(1, 'CT1', 'commit message is empty')];
    const ignored = classifyIgnored(title.text);
    if (ignored !== null && config.lint.ignore.includes(ignored)) return [];

    const result: LintDiagnostic[] = [];
    const header = title.text;
    const headerLength = codePointLength(header);
    if (headerLength > config.lint.header.maxLength) {
      result.push(diagnostic(title.number, 'T1', `header exceeds ${config.lint.header.maxLength} characters`));
    }
    if (header !== header.trimEnd()) result.push(diagnostic(title.number, 'T2', 'header has trailing whitespace'));
    if (header.includes('\t')) result.push(diagnostic(title.number, 'T4', 'header contains a hard tab'));
    if (config.lint.header.forbidTrailingPunctuation && /[?:!.,;]$/.test(header)) {
      result.push(diagnostic(title.number, 'T3', 'header has forbidden trailing punctuation'));
    }
    for (const word of config.lint.header.forbiddenWords) {
      const escaped = word.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      if (new RegExp(`\\b${escaped}\\b`, 'i').test(header)) {
        result.push(diagnostic(title.number, 'T5', `header contains forbidden word "${word}"`));
      }
    }
    if (headerLength < config.lint.header.minLength) {
      result.push(diagnostic(title.number, 'T8', `header is shorter than ${config.lint.header.minLength} characters`));
    }
    if (header !== header.trimStart()) {
      result.push(diagnostic(title.number, 'T6', 'header has leading whitespace'));
    }

    const parsed = parseCommitMessage(
      header +
        '\n' +
        lines
          .slice(1)
          .map(line => line.text)
          .join('\n'),
      config.keywords,
    );
    if (parsed.kind !== 'conventional') {
      result.push(diagnostic(title.number, 'CT1', 'header must match type(scope)!?: subject'));
    } else {
      const type = config.types.find(candidate => candidate.type === parsed.commit.type);
      if (type === undefined) {
        result.push(diagnostic(title.number, 'CT1', `unknown commit type "${parsed.commit.type}"`));
      } else if (parsed.commit.scope !== null) {
        const knownScope = Object.hasOwn(type.scopes, parsed.commit.scope);
        const specialScope = Object.hasOwn(config.specialScopes, parsed.commit.scope);
        if (!knownScope && !specialScope) {
          result.push(
            diagnostic(title.number, 'CT1', `unknown scope "${parsed.commit.scope}" for type "${type.type}"`),
          );
        }
      }
      if (parsed.commit.subject.trim().length === 0) {
        result.push(diagnostic(title.number, 'CT1', 'subject must not be empty'));
      }
    }

    const bodyLines = lines.slice(1);
    if (config.lint.body.requireBlankSecondLine && bodyLines.length > 0 && bodyLines[0]?.text !== '') {
      result.push(diagnostic(bodyLines[0]?.number ?? 2, 'B4', 'line 2 must be blank'));
    }
    for (const line of bodyLines) {
      if (codePointLength(line.text) > config.lint.body.maxLineLength) {
        result.push(diagnostic(line.number, 'B1', `body line exceeds ${config.lint.body.maxLineLength} characters`));
      }
      if (line.text !== line.text.trimEnd())
        result.push(diagnostic(line.number, 'B2', 'body line has trailing whitespace'));
      if (line.text.includes('\t')) result.push(diagnostic(line.number, 'B3', 'body line contains a hard tab'));
      for (const keyword of config.keywords) {
        if (line.text.trimStart().startsWith(keyword) && !line.text.trimStart().startsWith(`${keyword}: `)) {
          result.push(diagnostic(line.number, 'CT1', `breaking trailer "${keyword}" must use ": "`));
        }
      }
    }
    const bodyContent = bodyLines
      .slice(config.lint.body.requireBlankSecondLine ? 1 : 0)
      .map(line => line.text)
      .join('');
    if (codePointLength(bodyContent) > 0 && codePointLength(bodyContent) < config.lint.body.minLengthWhenPresent) {
      result.push(
        diagnostic(
          bodyLines.find(line => line.text.trim().length > 0)?.number ?? 3,
          'B5',
          `body is shorter than ${config.lint.body.minLengthWhenPresent} characters`,
        ),
      );
    }
    return result;
  }
}
