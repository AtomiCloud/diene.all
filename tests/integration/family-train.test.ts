import { describe, expect, test } from 'bun:test';

import type { Problem } from '../../src/entries/problems.ts';
import type { Result } from '../../src/entries/result.ts';
import { ConfigRegistry, loadConfig } from '../../src/entries/config.ts';
import { InMemoryConfigSource } from '../../src/entries/config-test-helper.ts';
import { InMemoryLoggerSink, InMemoryMetricsCollector } from '../../src/entries/interfaces-test-helper.ts';
import { defaultOtelBlock, initOtel } from '../../src/entries/otel.ts';
import { InMemoryTraceEmitter } from '../../src/entries/otel-test-helper.ts';
import { canonicalResourceKey } from '../../src/entries/auth.ts';
import { FakeAuthStateRetriever } from '../../src/entries/auth-test-helper.ts';
import {
  type BackendClientContext,
  createApiEngine,
  type LpsmCoordinate,
  registerApiProblems,
} from '../../src/entries/api.ts';
import { ProblemRegistry } from '../../src/entries/problems.ts';
import { registerStandardConfigs } from '../../src/entries/standard-config.ts';
import { startCache, startPostgres, type StartedPreset } from '../../src/entries/standard-config-test-helper.ts';

interface FamilyPayload {
  readonly postgres: string;
  readonly cache: string;
  readonly train: 'ready';
}

type PostgresPreset = Awaited<ReturnType<typeof startPostgres>>;
type CachePreset = Awaited<ReturnType<typeof startCache>>;

const stopStarted = async (...containers: readonly (StartedPreset<unknown> | undefined)[]): Promise<void> => {
  const stopped = await Promise.allSettled(containers.filter(value => value !== undefined).map(value => value.stop()));
  const failure = stopped.find((result): result is PromiseRejectedResult => result.status === 'rejected');
  if (failure !== undefined) throw failure.reason;
};

describe('ten-member family train', () => {
  test('composes config, telemetry seams, auth, API client tree, and Result against real databases', async () => {
    let postgres: PostgresPreset | undefined;
    let cache: CachePreset | undefined;
    let otelRuntime: ReturnType<typeof initOtel> | undefined;
    let testFailure: { readonly error: unknown } | undefined;

    try {
      const started = await Promise.allSettled([startPostgres(), startCache()]);
      if (started[0].status === 'fulfilled') postgres = started[0].value;
      if (started[1].status === 'fulfilled') cache = started[1].value;
      const failedStart = started.find((result): result is PromiseRejectedResult => result.status === 'rejected');
      if (failedStart !== undefined) throw failedStart.reason;
      if (postgres === undefined || cache === undefined) throw new Error('database presets did not start');

      const registry = registerStandardConfigs(ConfigRegistry.create(), {
        which: ['postgres', 'cache'] as const,
      });
      const loaded = await loadConfig(
        new InMemoryConfigSource({ base: { postgres: postgres.block, cache: cache.block } }),
        registry,
        { prefix: 'DIENE_E2E_' },
      );
      const postgresConfig = loaded('postgres')[postgres.key];
      const cacheConfig = loaded('cache')[cache.key];
      if (postgresConfig === undefined || cacheConfig === undefined) throw new Error('loaded preset key is missing');

      const logger = new InMemoryLoggerSink();
      const metrics = new InMemoryMetricsCollector();
      const traces = new InMemoryTraceEmitter();
      otelRuntime = initOtel(
        defaultOtelBlock,
        {
          landscape: 'integration',
          platform: 'test',
          service: 'family-train',
          module: 'integration',
          version: '0.0.0',
        },
        { environment: {}, seams: { logger, metrics, traces } },
      );
      expect(otelRuntime.loggerSink).toBe(logger);
      expect(otelRuntime.metricsCollector).toBe(metrics);
      expect(otelRuntime.traceEmitter).toBe(traces);

      const resource = Object.freeze({
        platform: 'test',
        landscape: 'integration',
        service: 'family-train',
        resourceName: 'api',
      });
      const resourceKey = await canonicalResourceKey(resource).unwrap();
      const retriever = new FakeAuthStateRetriever({
        tokenSet: { idToken: 'integration-id', accessTokens: { [resourceKey]: 'integration-access' } },
      });

      const problemRegistry = new ProblemRegistry({
        scheme: 'https',
        host: 'errors.test.atomi.cloud',
        landscape: 'integration',
        platform: 'test',
        service: 'family-train',
        module: 'integration',
      });
      const apiProblems = await registerApiProblems(problemRegistry).unwrap();
      const coordinate: LpsmCoordinate = Object.freeze({
        landscape: 'integration',
        platform: 'test',
        service: 'family-train',
        module: 'public',
      });

      const observed: { authorization: string | null } = { authorization: null };
      const payload: FamilyPayload = Object.freeze({
        postgres: `${postgresConfig.host}:${postgresConfig.port}`,
        cache: `${cacheConfig.host}:${cacheConfig.port}`,
        train: 'ready',
      });
      const createClient = (context: BackendClientContext) => ({
        family: {
          async load(): Promise<FamilyPayload> {
            await otelRuntime?.traceEmitter.emit({ name: 'family.load', attributes: { train: 'ready' } }).unwrap();
            const response = await context.fetch(`${context.baseUrl}/family`);
            return (await response.json()) as FamilyPayload;
          },
        },
      });

      const engine = await createApiEngine({
        problems: apiProblems,
        fetch: async (input, init) => {
          const request =
            input instanceof Request ? input : new Request(input instanceof URL ? input.toString() : input, init);
          observed.authorization = request.headers.get('authorization');
          return Response.json(payload);
        },
        bindings: [
          {
            coordinate,
            resource,
            baseUrl: 'https://family.integration.test',
            auth: retriever,
            createClient,
          },
        ],
      }).unwrap();
      const client = await engine.resolve<ReturnType<typeof createClient>>(coordinate).unwrap();
      const outcome: Result<FamilyPayload, Problem> = client.family.load();

      expect(await outcome.unwrap()).toEqual(payload);
      expect(observed.authorization).toBe('Bearer integration-access');
      expect(retriever.getTokenSetCalls).toBe(1);
      expect(traces.records).toEqual([{ name: 'family.load', attributes: { train: 'ready' } }]);
      expect(engine.list()).toHaveLength(1);
    } catch (error) {
      testFailure = { error };
    }

    const cleanup = await Promise.allSettled([otelRuntime?.shutdown(), stopStarted(cache, postgres)]);
    const cleanupFailure = cleanup.find((result): result is PromiseRejectedResult => result.status === 'rejected');
    if (testFailure !== undefined) throw testFailure.error;
    if (cleanupFailure !== undefined) throw cleanupFailure.reason;
  }, 120_000);
});
