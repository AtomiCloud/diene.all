import { describe, expect, it } from 'bun:test';
import { HookTemplate } from '../../../src/lib/release/hook-template';

describe('hook template', () => {
  const subject = new HookTemplate();

  it('should render commit text without shell quoting', () => {
    expect(subject.renderText('release ${version}\n${notes}', '1.0.0', 'notes\n')).toBe('release 1.0.0\nnotes');
  });

  it('should safely render unquoted, single-quoted, and double-quoted placeholders', () => {
    const value = 'spaces \'single\' "double" $(touch pwned); echo bad\nnext';
    const actual = subject.renderCommand(
      'hook ${version} \'${version}\' "${version}" ${notes} \'${notes}\' "${notes}"',
      value,
      `${value}\n`,
    );

    expect(actual).toContain(`'${value.replaceAll("'", `'"'"'`)}'`);
    expect(actual).toContain(`'${value.replaceAll("'", `'"'"'`)}'`);
    expect(actual).toContain(
      `"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('$', '\\$').replaceAll('`', '\\`')}"`,
    );
  });

  it('should reject ambiguous or unsupported shell quote states before execution', () => {
    expect(() => subject.renderCommand("hook '${version}", '1.0.0', 'notes')).toThrow('unterminated');
    expect(() => subject.renderCommand('hook \\${version}', '1.0.0', 'notes')).toThrow('must not escape');
    expect(() => subject.renderCommand("hook $'${version}'", '1.0.0', 'notes')).toThrow('ANSI-C');
  });

  it('should preserve ordinary escapes and reject trailing escapes and NUL bytes', () => {
    expect(subject.renderCommand('printf "\\n" ${version}', '1.0.0', 'notes')).toBe('printf "\\n" \'1.0.0\'');
    expect(() => subject.renderCommand('hook \\', '1.0.0', 'notes')).toThrow('ambiguous escape');
    expect(() => subject.renderCommand('hook\0${version}', '1.0.0', 'notes')).toThrow('hook template');
    expect(() => subject.renderCommand('${version}', '1.0.0\0', 'notes')).toThrow('hook version');
    expect(() => subject.renderCommand('${notes}', '1.0.0', 'notes\0')).toThrow('hook notes');
    expect(() => subject.renderCommand('hook $"${version}"', '1.0.0', 'notes')).toThrow('locale quote');
  });
});
