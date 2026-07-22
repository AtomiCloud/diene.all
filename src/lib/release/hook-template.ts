import { HookError } from '../errors';

type ShellContext = 'unquoted' | 'single' | 'double' | 'ansi-single' | 'locale-double';

const PLACEHOLDERS = ['${version}', '${notes}'] as const;

function quoteForShell(value: string): string {
  return `'${value.replaceAll("'", `'"'"'`)}'`;
}

function quoteForSingleQuotedContext(value: string): string {
  return value.replaceAll("'", `'"'"'`);
}

function quoteForDoubleQuotedContext(value: string): string {
  return value.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('$', '\\$').replaceAll('`', '\\`');
}

function placeholderAt(template: string, index: number): (typeof PLACEHOLDERS)[number] | null {
  return PLACEHOLDERS.find(candidate => template.startsWith(candidate, index)) ?? null;
}

function assertNoNul(value: string, subject: string): void {
  if (value.includes('\0')) throw new HookError(`${subject} must not contain a NUL byte`);
}

export class HookTemplate {
  renderText(template: string, version: string, notes: string): string {
    return template.replaceAll('${version}', version).replaceAll('${notes}', notes.trimEnd());
  }

  renderCommand(template: string, version: string, notes: string): string {
    const values: Readonly<Record<(typeof PLACEHOLDERS)[number], string>> = {
      '${version}': version,
      '${notes}': notes.trimEnd(),
    };
    assertNoNul(template, 'hook template');
    assertNoNul(version, 'hook version');
    assertNoNul(notes, 'hook notes');

    let context: ShellContext = 'unquoted';
    let rendered = '';
    let previousWasEscaped = false;
    for (let index = 0; index < template.length; ) {
      const placeholder = placeholderAt(template, index);
      if (placeholder !== null) {
        if (context === 'ansi-single' || context === 'locale-double') {
          throw new HookError(`hook placeholder ${placeholder} is not supported inside an ANSI-C or locale quote`);
        }
        const value = values[placeholder];
        rendered +=
          context === 'unquoted'
            ? quoteForShell(value)
            : context === 'single'
              ? quoteForSingleQuotedContext(value)
              : quoteForDoubleQuotedContext(value);
        index += placeholder.length;
        previousWasEscaped = false;
        continue;
      }

      const character = template[index] as string;
      if ((context === 'unquoted' || context === 'double' || context === 'locale-double') && character === '\\') {
        const next = template[index + 1];
        if (next === undefined) throw new HookError('hook template ends with an ambiguous escape');
        if (next === '$' && placeholderAt(template, index + 1) !== null) {
          throw new HookError('hook template must not escape a placeholder');
        }
        rendered += `${character}${next}`;
        index += 2;
        previousWasEscaped = true;
        continue;
      }

      if (context === 'unquoted') {
        if (character === "'") {
          context = index > 0 && template[index - 1] === '$' && !previousWasEscaped ? 'ansi-single' : 'single';
        } else if (character === '"') {
          context = index > 0 && template[index - 1] === '$' && !previousWasEscaped ? 'locale-double' : 'double';
        }
      } else if ((context === 'single' || context === 'ansi-single') && character === "'") {
        context = 'unquoted';
      } else if ((context === 'double' || context === 'locale-double') && character === '"') {
        context = 'unquoted';
      }

      rendered += character;
      index += 1;
      previousWasEscaped = false;
    }

    if (context !== 'unquoted') throw new HookError(`hook template has an unterminated ${context} quote`);
    return rendered;
  }
}
