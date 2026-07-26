import { resolve } from 'node:path';
import { setDefaultTimeout } from 'bun:test';
import { z } from 'zod';
import Redis from 'ioredis';
import postgres from 'postgres';
import { runApplication, type ApplicationIo } from '../../src/index';

setDefaultTimeout(120_000);

const root = resolve(import.meta.dir, '../..');
const devConfigSchema = z.object({
  clickhouse: z.object({ endpoint: z.url() }),
  encryption: z.object({ key: z.string().min(1) }),
  otel: z.object({ endpoint: z.url() }),
  postgres: z.object({
    database: z.string(),
    host: z.string(),
    password: z.string(),
    port: z.number().int(),
    username: z.string(),
  }),
  redis: z.object({ cacheDb: z.number().int(), host: z.string(), kvDb: z.number().int(), port: z.number().int() }),
  storage: z.object({
    accessKeyId: z.string(),
    endpoint: z.url(),
    secretAccessKey: z.string(),
  }),
  victoriaMetrics: z.object({ endpoint: z.url() }),
});

export const devConfig = devConfigSchema.parse(Bun.YAML.parse(await Bun.file(resolve(root, 'config/dev.yaml')).text()));

export interface CommandResult {
  readonly code: number;
  readonly err: string;
  readonly out: string;
}

export interface RunningCommand {
  stop(): Promise<CommandResult>;
}

export interface ConsumerDriver {
  run(args: readonly string[], environment?: Readonly<Record<string, string>>): Promise<CommandResult>;
  start(args: readonly string[], environment?: Readonly<Record<string, string>>): RunningCommand;
}

export const baseEnvironment: Readonly<Record<string, string>> = {
  ATOMI_AUTH__LOGTO__APP_ID: 'sit-consumer',
  ATOMI_AUTH__LOGTO__APP_SECRET: 'sit-secret',
  ATOMI_AUTH__LOGTO__MANAGEMENT__CLIENT_ID: 'sit-management',
  ATOMI_AUTH__LOGTO__MANAGEMENT__CLIENT_SECRET: 'sit-secret',
  ATOMI_CACHE__MAIN__HOST: devConfig.redis.host,
  ATOMI_CACHE__MAIN__PORT: String(devConfig.redis.port),
  ATOMI_CACHE__MAIN__DB: String(devConfig.redis.cacheDb),
  ATOMI_DB_INIT__CREATE_BUCKET: 'false',
  ATOMI_ENCRYPTION__KEY: devConfig.encryption.key,
  ATOMI_KV__MAIN__HOST: devConfig.redis.host,
  ATOMI_KV__MAIN__PORT: String(devConfig.redis.port),
  ATOMI_KV__MAIN__DB: String(devConfig.redis.kvDb),
  ATOMI_OTEL__LOGS__EXPORTER__OTLP__ENDPOINT: devConfig.otel.endpoint,
  ATOMI_OTEL__LOGS__EXPORTER__OTLP__ENABLED: 'true',
  ATOMI_OTEL__METRICS__EXPORTER__OTLP__ENDPOINT: devConfig.otel.endpoint,
  ATOMI_OTEL__METRICS__EXPORTER__OTLP__ENABLED: 'true',
  ATOMI_OTEL__TRACES__EXPORTER__OTLP__ENDPOINT: devConfig.otel.endpoint,
  ATOMI_OTEL__TRACES__EXPORTER__OTLP__ENABLED: 'true',
  ATOMI_POSTGRES__MAIN__DATABASE: devConfig.postgres.database,
  ATOMI_POSTGRES__MAIN__HOST: devConfig.postgres.host,
  ATOMI_POSTGRES__MAIN__PASSWORD: devConfig.postgres.password,
  ATOMI_POSTGRES__MAIN__PORT: String(devConfig.postgres.port),
  ATOMI_POSTGRES__MAIN__USERNAME: devConfig.postgres.username,
  ATOMI_STORAGE__ARCHIVE__ACCESS_KEY_ID: devConfig.storage.accessKeyId,
  ATOMI_STORAGE__ARCHIVE__ENDPOINT: devConfig.storage.endpoint,
  ATOMI_STORAGE__ARCHIVE__SECRET_ACCESS_KEY: devConfig.storage.secretAccessKey,
  ATOMI_STORAGE__MAIN__ACCESS_KEY_ID: devConfig.storage.accessKeyId,
  ATOMI_STORAGE__MAIN__ENDPOINT: devConfig.storage.endpoint,
  ATOMI_STORAGE__MAIN__SECRET_ACCESS_KEY: devConfig.storage.secretAccessKey,
  BUN_CONSUMER_ROOT: root,
};

export class BinaryConsumerDriver implements ConsumerDriver {
  constructor(readonly binary: string) {}

  async run(args: readonly string[], environment: Readonly<Record<string, string>> = {}): Promise<CommandResult> {
    const child = Bun.spawn([this.binary, ...args], {
      env: { ...process.env, ...baseEnvironment, ...environment },
      stderr: 'pipe',
      stdout: 'pipe',
    });
    const [code, err, out] = await Promise.all([
      child.exited,
      new Response(child.stderr).text(),
      new Response(child.stdout).text(),
    ]);
    return { code, err, out };
  }

  start(args: readonly string[], environment: Readonly<Record<string, string>> = {}): RunningCommand {
    const child = Bun.spawn([this.binary, ...args], {
      env: { ...process.env, ...baseEnvironment, ...environment },
      stderr: 'pipe',
      stdout: 'pipe',
    });
    return {
      stop: async () => {
        if (child.exitCode === null) child.kill('SIGTERM');
        const [code, err, out] = await Promise.all([
          child.exited,
          new Response(child.stderr).text(),
          new Response(child.stdout).text(),
        ]);
        return { code, err, out };
      },
    };
  }
}

export class InProcessConsumerDriver implements ConsumerDriver {
  async run(args: readonly string[], environment: Readonly<Record<string, string>> = {}): Promise<CommandResult> {
    let err = '';
    let out = '';
    const io: ApplicationIo = {
      error: message => {
        err += `${message}\n`;
      },
      output: message => {
        out += `${message}\n`;
      },
    };
    const code = await runApplication(['bun', 'bun-consumer', ...args], {
      environment: { ...process.env, ...baseEnvironment, ...environment },
      io,
      moduleDirectory: resolve(root, 'src'),
    });
    return { code, err, out };
  }

  start(args: readonly string[], environment: Readonly<Record<string, string>> = {}): RunningCommand {
    const result = this.run(args.includes('--once') ? args : [...args, '--once'], environment);
    return { stop: () => result };
  }
}

export function consumerDriver(): ConsumerDriver {
  return process.env.SIT_DRIVER === 'inprocess'
    ? new InProcessConsumerDriver()
    : new BinaryConsumerDriver(resolve(root, process.env.CLI_BIN ?? 'dist/bin/bun-consumer'));
}

export function redisClient(): Redis {
  return new Redis({ db: devConfig.redis.kvDb, host: devConfig.redis.host, port: devConfig.redis.port });
}

export function postgresClient(): ReturnType<typeof postgres> {
  return postgres({
    database: devConfig.postgres.database,
    host: devConfig.postgres.host,
    password: devConfig.postgres.password,
    port: devConfig.postgres.port,
    username: devConfig.postgres.username,
  });
}

export function storageClient(bucket = 'bun-consumer'): Bun.S3Client {
  return new Bun.S3Client({
    accessKeyId: devConfig.storage.accessKeyId,
    bucket,
    endpoint: devConfig.storage.endpoint,
    region: 'us-east-1',
    secretAccessKey: devConfig.storage.secretAccessKey,
    virtualHostedStyle: false,
  });
}

export async function initialize(driver: ConsumerDriver): Promise<CommandResult> {
  return driver.run(['db-init']);
}

export async function waitFor(assertion: () => boolean | Promise<boolean>, timeoutMs = 30_000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await assertion()) return;
    await Bun.sleep(250);
  }
  throw new Error(`condition was not met within ${timeoutMs}ms`);
}

export async function closeSafely(resource: {
  end?: (options?: { timeout: number }) => unknown;
  quit?: () => unknown;
}): Promise<void> {
  try {
    if (resource.quit) await resource.quit();
    else if (resource.end) await resource.end({ timeout: 1 });
  } catch {}
}
