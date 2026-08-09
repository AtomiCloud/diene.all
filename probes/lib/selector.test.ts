import { describe, expect, test } from 'bun:test';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

// RB-286 regression guard.
//
// `flutter test --plain-name` is a plain-text substring selector; `--name` is
// the regular-expression selector. A selector value containing a regex
// alternation (`|`) is only meaningful under `--name` — pairing `|` with
// `--plain-name` searches for a literal pipe, matches no test, and leaves the
// baseline permanently red (the RB-286 defect on `problem-local-error`).

const probesDir = join(import.meta.dir, '..');

function probeSources(): Array<{ name: string; text: string }> {
  return readdirSync(probesDir)
    .filter(entry => entry.endsWith('.ts'))
    .map(entry => ({ name: entry, text: readFileSync(join(probesDir, entry), 'utf8') }));
}

function selectorValues(text: string, flag: '--name' | '--plain-name'): string[] {
  const pattern = new RegExp(`${flag} '([^']*)'`, 'g');
  return [...text.matchAll(pattern)].map(match => match[1]);
}

describe('flutter selector discipline', () => {
  test('no --plain-name selector uses a regex alternation', () => {
    for (const probe of probeSources()) {
      for (const value of selectorValues(probe.text, '--plain-name')) {
        expect(
          value.includes('|'),
          `${probe.name}: '${value}' is a regex alternation and must use --name, not --plain-name`,
        ).toBeFalse();
      }
    }
  });

  test('problem-local-error selects LocalError and ProblemVisualizer via the regex selector', () => {
    const source = readFileSync(join(probesDir, 'problem-local-error.ts'), 'utf8');
    expect(source).not.toContain('--plain-name');
    expect(selectorValues(source, '--name')).toContain('LocalError|ProblemVisualizer');
  });
});
