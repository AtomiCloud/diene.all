import type { CommitClassification, CommitFooter, ConventionalCommit } from './model';

const HEADER = /^([a-z][a-z0-9-]*)(?:\(([^()\r\n]+)\))?(!)?: (.+)$/;

const IGNORE_PREFIXES: ReadonlyArray<readonly [RegExp, 'merge' | 'revert' | 'fixup' | 'fixup-amend' | 'squash']> = [
  [/^Merge /, 'merge'],
  [/^Revert /, 'revert'],
  [/^fixup! /, 'fixup'],
  [/^amend! /, 'fixup-amend'],
  [/^squash! /, 'squash'],
];

export function normalizeCommitMessage(message: string): string {
  return message.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

export function classifyIgnored(message: string): 'merge' | 'revert' | 'fixup' | 'fixup-amend' | 'squash' | null {
  const firstLine = normalizeCommitMessage(message).split('\n', 1)[0] ?? '';
  for (const [pattern, reason] of IGNORE_PREFIXES) if (pattern.test(firstLine)) return reason;
  return null;
}

function parseFooters(rest: string): { body: string; footers: CommitFooter[] } {
  const footers: CommitFooter[] = [];
  const bodyLines: string[] = [];
  for (const line of rest.split('\n')) {
    const match = /^([A-Za-z][A-Za-z-]*(?: [A-Z]+)*): (.+)$/.exec(line);
    if (match?.[1] !== undefined && match[2] !== undefined) {
      footers.push({ token: match[1], value: match[2] });
    } else {
      bodyLines.push(line);
    }
  }
  return { body: bodyLines.join('\n').trim(), footers };
}

function hasBreakingKeyword(rest: string, keywords: readonly string[]): boolean {
  return normalizeCommitMessage(rest)
    .split('\n')
    .some(line => keywords.some(keyword => line.trimStart().startsWith(`${keyword}:`)));
}

export function parseCommitMessage(message: string, keywords: readonly string[]): CommitClassification {
  const normalized = normalizeCommitMessage(message);
  const ignored = classifyIgnored(normalized);
  if (ignored !== null) return { kind: 'ignored', reason: ignored };
  const [header = '', ...restLines] = normalized.split('\n');
  const match = HEADER.exec(header);
  if (match === null) return { kind: 'malformed' };
  const rest = restLines.join('\n');
  const { body, footers } = parseFooters(rest);
  const commit: ConventionalCommit = {
    type: match[1] as string,
    scope: match[2] ?? null,
    breaking: match[3] === '!' || hasBreakingKeyword(rest, keywords),
    subject: match[4] as string,
    body,
    footers,
  };
  return { kind: 'conventional', commit };
}
