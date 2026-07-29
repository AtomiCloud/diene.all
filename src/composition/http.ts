import { Hono } from 'hono';

export type MercuryDependencyState = 'degraded' | 'ok';

export interface MercuryReadinessReport {
  readonly ready: boolean;
  readonly dependencies: Readonly<Record<string, MercuryDependencyState>>;
}

export interface MercuryHttpApplicationInput {
  readonly management: Hono;
  readonly console: Hono;
  readonly landscape: Hono;
  readonly intake: (request: Request) => Promise<Response>;
  readonly startupComplete: () => boolean;
  readonly readiness: () => Promise<MercuryReadinessReport>;
  readonly metrics: () => Promise<{ readonly body: string; readonly contentType: string }>;
}

const missingSurface = (surface: string): Response =>
  Response.json({ error: 'not_found', message: `${surface} route not found` }, { status: 404 });

/** Mounts every production surface before the public intake catch-all. */
export function createMercuryHttpApplication(input: MercuryHttpApplicationInput): Hono {
  const app = new Hono();

  app.get('/health/live', context => context.json({ product: 'mercury.webhook', status: 'live' }));
  app.get('/health/startup', context =>
    input.startupComplete()
      ? context.json({ product: 'mercury.webhook', status: 'started' })
      : context.json({ product: 'mercury.webhook', status: 'starting' }, 503),
  );
  app.get('/health/ready', async context => {
    const report = await input.readiness();
    return context.json(report, report.ready ? 200 : 503);
  });
  app.get('/metrics', async () => {
    const metrics = await input.metrics();
    return new Response(metrics.body, { headers: { 'content-type': metrics.contentType } });
  });

  app.route('/management/v1', input.management);
  app.route('/internal/landscape/v1', input.landscape);
  app.route('/', input.console);

  // Reserved product surfaces must never fall through to tenant intake.
  app.all('/health/*', () => missingSurface('health'));
  app.all('/management/v1/*', () => missingSurface('management'));
  app.all('/internal/landscape/v1/*', () => missingSurface('landscape'));
  app.all('/console/*', () => missingSurface('console'));

  app.post('*', context => input.intake(context.req.raw));

  return app;
}
