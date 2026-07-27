import { describe, expect, test } from 'bun:test';

import { createBrunoEnvironment, E2eHarnessError, resolveGardenPreviewEndpoint } from '../../src/test-helper/index.ts';

const namespace = Object.freeze({
  module: 'public',
  service: 'orders',
  platform: 'commerce',
  instance: 'pr-417',
  landscape: 'eevee',
  zone: 'preview.atomi.cloud',
});
const hostname = 'public.orders.commerce.pr-417.eevee.preview.atomi.cloud';

describe('Garden preview endpoint assertion glue', () => {
  test('accepts the known-good final dotted namespace and defaults to HTTPS', () => {
    expect(resolveGardenPreviewEndpoint({ hostname, namespace, path: '/healthz' })).toBe(`https://${hostname}/healthz`);
  });

  test('allows an explicitly configured HTTP endpoint and port', () => {
    expect(resolveGardenPreviewEndpoint({ hostname, namespace, protocol: 'http', port: 8080 })).toBe(
      `http://${hostname}:8080/`,
    );
  });

  test('proves the asserter rejects a known-bad mismatched namespace fixture', () => {
    expect(() => resolveGardenPreviewEndpoint({ hostname, namespace: { ...namespace, instance: 'pr-418' } })).toThrow(
      E2eHarnessError,
    );
  });

  test('rejects malformed names, ports, and paths', () => {
    expect(() => resolveGardenPreviewEndpoint({ hostname, namespace: { ...namespace, module: 'Public' } })).toThrow(
      'namespace.module must be a lowercase DNS name',
    );
    expect(() => resolveGardenPreviewEndpoint({ hostname: 'https://not-a-host', namespace })).toThrow(
      'hostname must be a lowercase DNS name',
    );
    expect(() => resolveGardenPreviewEndpoint({ hostname, namespace, port: 0 })).toThrow('port must be an integer');
    expect(() => resolveGardenPreviewEndpoint({ hostname, namespace, path: '//escape' })).toThrow(
      'path must be an absolute URL path',
    );
  });
});

describe('Bruno environment glue', () => {
  test('returns a frozen, string-only collection environment', () => {
    const environment = createBrunoEnvironment({
      baseUrl: `https://${hostname}/`,
      accessToken: 'token',
      variables: { tenant: 'demo' },
    });
    expect(environment).toEqual({ baseUrl: `https://${hostname}`, accessToken: 'token', tenant: 'demo' });
    expect(Object.isFrozen(environment)).toBe(true);
  });

  test('rejects unusable URLs and variables', () => {
    expect(() => createBrunoEnvironment({ baseUrl: 'relative' })).toThrow('baseUrl must be an absolute');
    expect(() => createBrunoEnvironment({ baseUrl: 'ftp://example.test' })).toThrow('HTTP(S) URL');
    expect(() => createBrunoEnvironment({ baseUrl: 'https://user:secret@example.test' })).toThrow(
      'without credentials',
    );
    expect(() => createBrunoEnvironment({ baseUrl: 'https://example.test', variables: { 'not valid': 'x' } })).toThrow(
      'identifier keys',
    );
    expect(() =>
      createBrunoEnvironment({
        baseUrl: 'https://example.test',
        variables: { invalid: 1 } as unknown as Record<string, string>,
      }),
    ).toThrow('string values');
    expect(() =>
      createBrunoEnvironment({
        baseUrl: 'https://example.test',
        accessToken: 7 as unknown as string,
      }),
    ).toThrow('accessToken must be a string');
  });
});
