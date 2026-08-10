import { describe, expect, test } from 'bun:test';
import type { ProbeExecResult, ProbeRepo } from '@cyanprint/contracts';
import { packPackages } from './dotnet-package';

class RecordingRepo implements ProbeRepo {
  readonly commands: string[] = [];
  readonly timeouts: Array<number | undefined> = [];

  async exec(command: string, options?: { timeoutMs?: number }): Promise<ProbeExecResult> {
    this.commands.push(command);
    this.timeouts.push(options?.timeoutMs);
    return { exitCode: 0, stdout: '', stderr: '' };
  }

  async read(): Promise<string> {
    throw new Error('unused');
  }

  async write(): Promise<void> {
    throw new Error('unused');
  }

  async remove(): Promise<void> {
    throw new Error('unused');
  }

  async glob(): Promise<string[]> {
    return [];
  }

  async patch(): Promise<void> {
    throw new Error('unused');
  }
}

describe('packPackages helper', () => {
  test('packs the release configuration into the shared artifacts directory', async () => {
    const repo = new RecordingRepo();
    await packPackages(repo, 'pack-label');
    expect(repo.commands).toHaveLength(1);
    expect(repo.commands[0]).toContain('dotnet pack dotnet-base.slnx -c Release');
    expect(repo.commands[0]).toContain('--output artifacts/package');
  });

  test('restores before packing rather than reusing the stale --no-restore flag', async () => {
    const repo = new RecordingRepo();
    await packPackages(repo, 'pack-label');
    // The accepted CI repair removed --no-restore from `dotnet pack`; the probe
    // helper must match so the three package probes restore before packing.
    expect(repo.commands[0]).not.toContain('--no-restore');
  });

  test('removes copied build intermediates before packing the current probe state', async () => {
    const repo = new RecordingRepo();
    await packPackages(repo, 'pack-label');
    const command = repo.commands[0];
    const clean = 'find . -mindepth 2 -maxdepth 2 -type d \\( -name bin -o -name obj \\) -prune -exec rm -rf {} +';
    expect(command).toContain(clean);
    expect(command.indexOf(clean)).toBeLessThan(command.indexOf('dotnet pack'));
  });
});
