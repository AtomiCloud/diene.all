import { resolve } from 'node:path';
import { CommanderError, Command } from 'commander';
import { safeJoin } from '@atomicloud/diene.e2e/core-utils';
import { initOtel, type OtelRuntime } from '@atomicloud/diene.e2e/otel';
import { named } from '@atomicloud/diene.e2e/standard-config';
import { buildPublishedClients, type PublishedClients } from './api/published-clients';
import { buildPostgresAdapters, type PostgresAdapter } from './adapters/postgres';
import { buildRedisAdapters, type RedisAdapter } from './adapters/redis';
import { RedisStreamsTransport } from './adapters/redis-streams';
import { buildStorageAdapters, type StorageAdapter } from './adapters/storage';
import { Cache, Kv, Postgres, Storage } from './config/constants';
import { loadApplicationConfig } from './config/load';
import type { ApplicationConfig } from './config/schema';
import { SampleWorkerHandler } from './domain/handler';
import { createDomainProblems } from './domain/problems';
import { FileHeartbeat } from './health/heartbeat';
import { McBucketProvisioner } from './init/bucket';
import { DatabaseInitializer } from './init/db-initializer';
import { MigrationRunner } from './init/migrations';
import { ReachabilityChecks } from './init/reachability';
import { SeedLoader } from './init/seeds';
import { Aes256GcmEncryptor } from './lib/encryption';
import { ConsumerWorker } from './worker/consumer';

export const ARTIFACT_NAME = 'bun-consumer';
export const CONFIG_PREFIX = 'ATOMI_';

export interface ApplicationIo {
  error(message: string): void;
  output(message: string): void;
}

export interface ApplicationOptions {
  readonly environment?: NodeJS.ProcessEnv;
  readonly io?: ApplicationIo;
  readonly moduleDirectory?: string;
}

export interface RuntimeResources {
  readonly cache: ReadonlyMap<string, RedisAdapter>;
  readonly config: ApplicationConfig;
  readonly kv: ReadonlyMap<string, RedisAdapter>;
  readonly postgres: ReadonlyMap<string, PostgresAdapter>;
  readonly published: PublishedClients;
  readonly storage: ReadonlyMap<string, StorageAdapter>;
  readonly telemetry: OtelRuntime;
}

export function requireAdapter<T>(adapters: ReadonlyMap<string, T>, key: string): T {
  const adapter = adapters.get(key);
  if (!adapter) throw new Error(`configured adapter '${key}' was not constructed`);
  return adapter;
}

export function repositoryRoot(environment: NodeJS.ProcessEnv, moduleDirectory: string): string {
  return resolve(environment.BUN_CONSUMER_ROOT ?? resolve(moduleDirectory, '..'));
}

export async function createRuntime(config: ApplicationConfig): Promise<RuntimeResources> {
  const telemetry = initOtel(config.otel, config.app);
  named(config.postgres, Postgres.Main);
  named(config.cache, Cache.Main);
  named(config.kv, Kv.Main);
  named(config.storage, Storage.Main);
  const problems = createDomainProblems(config.errorPortal, config.transport.stream, config.errorPortal.version);
  const published = await buildPublishedClients(config, problems.registry);
  const postgres = buildPostgresAdapters(config.postgres, telemetry.tracer);
  const cache = buildRedisAdapters(config.cache, telemetry.tracer, 'cache');
  const kv = buildRedisAdapters(config.kv, telemetry.tracer, 'kv');
  const storage = buildStorageAdapters(config.storage, telemetry.tracer);
  telemetry.logger.info(
    { apiBackends: published.api.list().length, storageInstances: storage.size },
    'runtime constructed',
  );
  return { cache, config, kv, postgres, published, storage, telemetry };
}

export async function closeRuntime(runtime: RuntimeResources): Promise<void> {
  for (const adapter of runtime.postgres.values()) {
    try {
      await adapter.close();
    } catch (error) {
      runtime.telemetry.logger.warn({ error }, 'postgres teardown failed');
    }
  }
  for (const adapter of [...runtime.cache.values(), ...runtime.kv.values()]) {
    try {
      await adapter.close();
    } catch (error) {
      adapter.client.disconnect();
      runtime.telemetry.logger.warn({ error }, 'redis teardown failed');
    }
  }
  try {
    await runtime.telemetry.shutdown();
  } catch (error) {
    console.error('telemetry teardown failed', error);
  }
}

export async function loadConfigForCommand(
  root: string,
  environment: NodeJS.ProcessEnv,
  landscape?: string,
): Promise<ApplicationConfig> {
  const configDirectory = environment.BUN_CONSUMER_CONFIG_DIR ?? 'config';
  return loadApplicationConfig({
    configDir: safeJoin(root, ...configDirectory.split('/')),
    environment,
    landscape,
    prefix: CONFIG_PREFIX,
  });
}

export function createProgram(options: ApplicationOptions = {}): Command {
  const environment = options.environment ?? process.env;
  const io = options.io ?? { error: message => console.error(message), output: message => console.log(message) };
  const root = repositoryRoot(environment, options.moduleDirectory ?? import.meta.dir);
  const program = new Command()
    .name(ARTIFACT_NAME)
    .description('Config-driven Redis streams worker consumer')
    .addHelpCommand(false);
  program.option('--landscape <name>', 'select a sparse landscape overlay');

  program
    .command('worker')
    .description('run the long-lived Redis streams consumer')
    .option('--once', 'process one polling cycle and stop', false)
    .action(async commandOptions => {
      const globalOptions = program.opts<{ landscape?: string }>();
      const config = await loadConfigForCommand(root, environment, globalOptions.landscape);
      const runtime = await createRuntime(config);
      const abort = new AbortController();
      const stop = () => abort.abort();
      process.once('SIGINT', stop);
      process.once('SIGTERM', stop);
      try {
        const postgres = requireAdapter(runtime.postgres, Postgres.Main);
        const redis = requireAdapter(runtime.kv, Kv.Main);
        const storage = requireAdapter(runtime.storage, Storage.Main);
        await redis.connect().match({ err: error => Promise.reject(error), ok: () => undefined });

        // ─── DOMAIN WIRING · bun-consumer sample ───
        const handler = new SampleWorkerHandler(
          postgres,
          storage,
          new Aes256GcmEncryptor(config.encryption.key),
          config.domain.blobPrefix,
        );
        const transport = new RedisStreamsTransport(redis.client, runtime.telemetry.tracer, config.transport);
        const heartbeat = new FileHeartbeat(
          safeJoin(root, ...config.health.heartbeatFile.split('/')),
          config.health.maxAgeMs,
        );
        const worker = new ConsumerWorker(
          transport,
          handler,
          heartbeat,
          runtime.telemetry,
          config.domain.maxMessageBytes,
          {
            'atomi.consumer.name': config.transport.consumerName,
            'atomi.landscape': config.app.landscape,
            'atomi.module': config.app.module,
            'atomi.platform': config.app.platform,
            'atomi.service': config.app.service,
            'atomi.transport.stream': config.transport.stream,
          },
        );
        // ─── END DOMAIN WIRING · bun-consumer sample ───

        await worker.run(abort.signal, commandOptions.once === true);
      } finally {
        process.off('SIGINT', stop);
        process.off('SIGTERM', stop);
        await closeRuntime(runtime);
      }
    });

  program
    .command('db-init')
    .description('check dependencies, migrate, and seed idempotently')
    .action(async () => {
      const globalOptions = program.opts<{ landscape?: string }>();
      const config = await loadConfigForCommand(root, environment, globalOptions.landscape);
      const runtime = await createRuntime(config);
      try {
        const postgres = requireAdapter(runtime.postgres, Postgres.Main);
        const redis = requireAdapter(runtime.kv, Kv.Main);
        await redis.connect().match({ err: error => Promise.reject(error), ok: () => undefined });
        const reachability = new ReachabilityChecks(
          [...runtime.postgres.values()],
          [...runtime.cache.values(), ...runtime.kv.values()],
          [...runtime.storage.values()],
          new McBucketProvisioner(),
          config.dbInit.createBucket,
        );
        const migrations = new MigrationRunner(
          postgres,
          redis,
          safeJoin(root, ...config.dbInit.migrationsDir.split('/')),
          config.dbInit.redisMigrationKey,
        );
        // ─── DOMAIN WIRING · bun-consumer seed sample ───
        const seeds = new SeedLoader(postgres, safeJoin(root, ...config.dbInit.seedDir.split('/')));
        // ─── END DOMAIN WIRING · bun-consumer seed sample ───
        const result = await new DatabaseInitializer(reachability, migrations, seeds).run();
        io.output(JSON.stringify({ ok: true, ...result }));
      } finally {
        await closeRuntime(runtime);
      }
    });

  program
    .command('health')
    .description('check the dependency-blind worker heartbeat')
    .action(async () => {
      const globalOptions = program.opts<{ landscape?: string }>();
      const config = await loadConfigForCommand(root, environment, globalOptions.landscape);
      const heartbeat = new FileHeartbeat(
        safeJoin(root, ...config.health.heartbeatFile.split('/')),
        config.health.maxAgeMs,
      );
      const result = await heartbeat.check();
      io.output(JSON.stringify(result));
      if (!result.healthy) throw new Error(result.reason);
    });

  return program;
}

export async function runApplication(argv: readonly string[], options: ApplicationOptions = {}): Promise<number> {
  const io = options.io ?? { error: message => console.error(message), output: message => console.log(message) };
  const program = createProgram({ ...options, io });
  program.exitOverride();
  program.configureOutput({
    writeErr: value => io.error(value.trimEnd()),
    writeOut: value => io.output(value.trimEnd()),
  });
  try {
    await program.parseAsync([...argv], { from: 'node' });
    return 0;
  } catch (error) {
    if (error instanceof CommanderError) return error.exitCode;
    io.error(error instanceof Error ? error.message : String(error));
    return 1;
  }
}

if (import.meta.main) process.exitCode = await runApplication(process.argv);
