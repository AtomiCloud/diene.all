import { describe, expect, test } from 'bun:test';
import { expectGreen } from './helpers';

describe('probe result reporting', () => {
  test('attributes a failed command and preserves both output streams', async () => {
    const command = 'run the failing gate';
    const repo = {
      exec: async () => ({ exitCode: 2, stdout: 'earlier output\n', stderr: 'later error\n' }),
    };

    let failure: unknown;
    try {
      await expectGreen(repo, command, 'binary-smoke');
    } catch (error) {
      failure = error;
    }

    expect(failure).toBeInstanceOf(Error);
    const message = (failure as Error).message;
    expect(message).toContain(`command failed (2): ${command}`);
    expect(message).toContain('stdout:\nearlier output');
    expect(message).toContain('stderr:\nlater error');
  });
});
