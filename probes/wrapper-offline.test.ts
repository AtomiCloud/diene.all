import { describe, expect, test } from 'bun:test';
import type { ProbeExecResult } from '@cyanprint/contracts';
import {
  expectGreenOrOffline,
  isConnectivityFailure,
  isProbeInapplicable,
  probeInapplicable,
} from './wrapper-offline.ts';

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

describe('probeInapplicable', () => {
  test('stamps the marker exactly like the engine contract (non-enumerable, read by name)', () => {
    const error = probeInapplicable('offline');
    // Detected across module realms by property name, never instanceof:
    expect(isProbeInapplicable(error)).toBe(true);
    // The official contract descriptor: value true, the rest default (false).
    const desc = Object.getOwnPropertyDescriptor(error, INAPPLICABLE);
    expect(desc?.value).toBe(true);
    expect(desc?.enumerable).toBe(false);
    expect(desc?.configurable).toBe(false);
    expect(desc?.writable).toBe(false);
    // Non-enumerable, so it never leaks into keys or serialized logs:
    expect(Object.keys(error)).not.toContain(INAPPLICABLE);
  });
});

describe('isProbeInapplicable', () => {
  test('rejects ordinary errors and non-marked values', () => {
    expect(isProbeInapplicable(new Error('ordinary'))).toBe(false);
    expect(isProbeInapplicable({})).toBe(false);
    expect(isProbeInapplicable({ cyanprintProbeInapplicable: 'true' })).toBe(false);
    expect(isProbeInapplicable(null)).toBe(false);
    expect(isProbeInapplicable(undefined)).toBe(false);
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
