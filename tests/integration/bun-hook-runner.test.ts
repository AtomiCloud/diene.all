import { afterEach, describe, expect, it } from 'bun:test';
import { mkdtemp, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { BunHookRunner } from '../../src/adapters/process/bun-hook-runner';
import { HookTemplate } from '../../src/lib/release/hook-template';

const roots: string[] = [];

afterEach(async () => {
  await Promise.all(roots.splice(0).map(path => rm(path, { recursive: true })));
});

describe('Bun hook runner', () => {
  it('should preserve exact bytes in unquoted, single-quoted, and double-quoted placeholders', async () => {
    // Arrange
    const cwd = await mkdtemp(join(tmpdir(), 'releaser-hook-'));
    roots.push(cwd);
    const version = '1.0.0 spaces \'single\' "double" $(touch pwned); echo bad\nnext';
    const notes = 'notes spaces \'single\' "double" $(touch pwned); echo bad\nnext';
    const command = new HookTemplate().renderCommand(
      "printf '%s\\0' ${version} '${version}' \"${version}\" ${notes} '${notes}' \"${notes}\" > captured.bin",
      version,
      notes,
    );
    const subject = new BunHookRunner(cwd, process.env);

    // Act
    await subject.run(command);

    // Assert
    expect(await Bun.file(join(cwd, 'pwned')).exists()).toBe(false);
    const actual = new Uint8Array(await Bun.file(join(cwd, 'captured.bin')).arrayBuffer());
    const expected = new TextEncoder().encode(`${version}\0${version}\0${version}\0${notes}\0${notes}\0${notes}\0`);
    expect(actual).toEqual(expected);
  });

  it('should propagate a nonzero exit while redacting inherited secrets', async () => {
    // Arrange
    const cwd = await mkdtemp(join(tmpdir(), 'releaser-hook-'));
    roots.push(cwd);
    const subject = new BunHookRunner(cwd, { ...process.env, SECRET_TOKEN: 'highly-sensitive' });

    // Act / Assert
    await expect(subject.run('printf "%s" "$SECRET_TOKEN" >&2; exit 7')).rejects.toThrow('[redacted]');
    await expect(subject.run('printf "%s" "$SECRET_TOKEN" >&2; exit 7')).rejects.not.toThrow('highly-sensitive');
  });
});
