import { describe, expect, test } from 'bun:test';
import type { ProbeExecResult } from '@cyanprint/contracts';
import { expectGreenOrOffline, inapplicableError, isConnectivityFailure } from './helpers.ts';

const INAPPLICABLE = 'cyanprintProbeInapplicable';

class ResultRepo {
  constructor(private readonly result: ProbeExecResult) {}

  async exec(_command: string, _options?: unknown): Promise<ProbeExecResult> {
    return this.result;
  }
}

async function rejection(callback: () => Promise<unknown>): Promise<unknown> {
  try {
    await callback();
  } catch (error) {
    return error;
  }
  throw new Error('expected the call to throw, but it resolved');
}

describe('isConnectivityFailure', () => {
  test('recognises credible connectivity indicators', () => {
    const samples = [
      'Get "https://ghcr.io/podinfo": dial tcp: lookup ghcr.io: no such host',
      'curl: (6) Could not resolve host: ghcr.io',
      'connect: network is unreachable',
      'dial tcp 10.0.0.1:443: connect: connection refused',
      'read tcp: connection reset by peer',
      'net/http: TLS handshake timeout',
      'Get "...": read: i/o timeout',
      'rpc error: code = DeadlineExceeded desc = context deadline exceeded',
    ];
    for (const sample of samples) {
      expect(isConnectivityFailure(sample)).toBe(true);
    }
  });

  test('matches line-wrapped resolver output', () => {
    const detail = ['Error: Get "https://ghcr.io": dial tcp:', '  lookup ghcr.io: no such host'].join('\n');
    expect(isConnectivityFailure(detail)).toBe(true);
  });

  test('does not hide semantic, HTTP, or local failures', () => {
    const samples = [
      'unexpected status code 404',
      'Error: 401 Unauthorized',
      'chart "podinfo" not found',
      'no chart version found for podinfo',
      'skopeo: command not found',
      'open chart/Chart.yaml: no such file or directory',
      'permission denied',
    ];
    for (const sample of samples) {
      expect(isConnectivityFailure(sample)).toBe(false);
    }
  });
});

describe('inapplicableError', () => {
  test('stamps the non-enumerable CyanPrint marker', () => {
    const error = inapplicableError('offline');
    expect((error as unknown as Record<string, unknown>)[INAPPLICABLE]).toBe(true);
    expect(Object.keys(error)).not.toContain(INAPPLICABLE);
    expect(Object.getOwnPropertyDescriptor(error, INAPPLICABLE)?.enumerable).toBe(false);
  });
});

describe('expectGreenOrOffline', () => {
  test('passes a green command', async () => {
    await expectGreenOrOffline(new ResultRepo({ exitCode: 0, stdout: 'ok', stderr: '' }), 'cmd', 'label');
  });

  test('marks a verified connectivity failure inapplicable', async () => {
    const repo = new ResultRepo({ exitCode: 1, stdout: '', stderr: 'lookup ghcr.io: no such host' });
    const error = (await rejection(() => expectGreenOrOffline(repo, 'cmd', 'label'))) as Record<string, unknown>;
    expect(error[INAPPLICABLE]).toBe(true);
  });

  test('keeps HTTP and script failures broken', async () => {
    for (const stderr of ['unexpected status code 404', 'skopeo: command not found']) {
      const repo = new ResultRepo({ exitCode: 1, stdout: '', stderr });
      const error = (await rejection(() => expectGreenOrOffline(repo, 'cmd', 'label'))) as Record<string, unknown>;
      expect(error[INAPPLICABLE]).toBeUndefined();
      expect(error).toBeInstanceOf(Error);
    }
  });
});
