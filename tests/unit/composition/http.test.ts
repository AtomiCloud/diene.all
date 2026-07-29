import { describe, expect, test } from 'bun:test';
import { Hono } from 'hono';
import { createMercuryHttpApplication } from '../../../src/composition/http.ts';

const surface = (path: string, name: string): Hono => {
  const app = new Hono();
  app.get(path, context => context.text(name));
  return app;
};

describe('Mercury HTTP composition', () => {
  test('mounts product surfaces before the name-blind intake catch-all', async () => {
    const intakePaths: string[] = [];
    const app = createMercuryHttpApplication({
      management: surface('/ping', 'management'),
      console: surface('/console', 'console'),
      landscape: surface('/ping', 'landscape'),
      intake: async request => {
        intakePaths.push(new URL(request.url).pathname);
        return new Response(null, { status: 200 });
      },
      startupComplete: () => true,
      readiness: async () => ({ ready: true, dependencies: { postgres: 'ok', redis: 'ok' } }),
      metrics: async () => ({ body: 'mercury_test 1\n', contentType: 'text/plain; version=0.0.4' }),
    });

    expect(await (await app.request('/management/v1/ping')).text()).toBe('management');
    expect(await (await app.request('/internal/landscape/v1/ping')).text()).toBe('landscape');
    expect(await (await app.request('/console')).text()).toBe('console');
    expect((await app.request('/t/acme/stripe', { method: 'POST' })).status).toBe(200);
    expect((await app.request('/management/v1/missing', { method: 'POST' })).status).toBe(404);
    expect(intakePaths).toEqual(['/t/acme/stripe']);
  });

  test('reports startup/readiness and preserves the metrics content type', async () => {
    const app = createMercuryHttpApplication({
      management: new Hono(),
      console: new Hono(),
      landscape: new Hono(),
      intake: async () => new Response(null, { status: 404 }),
      startupComplete: () => false,
      readiness: async () => ({ ready: false, dependencies: { postgres: 'degraded', redis: 'ok' } }),
      metrics: async () => ({ body: 'metric 2\n', contentType: 'text/plain; version=0.0.4' }),
    });

    expect((await app.request('/health/live')).status).toBe(200);
    expect((await app.request('/health/startup')).status).toBe(503);
    expect((await app.request('/health/ready')).status).toBe(503);
    const metrics = await app.request('/metrics');
    expect(metrics.headers.get('content-type')).toBe('text/plain; version=0.0.4');
    expect(await metrics.text()).toBe('metric 2\n');
  });
});
