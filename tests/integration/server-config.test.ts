import { afterEach, describe, it } from 'bun:test';
import should from 'should';
import { intConfig } from './fixtures/config';
import type { RootConfig } from '../../src/adapters/server-config';

// Integration: the config composition root. Landscape is READ from the host
// runtime and never browser-detected, the four-tier tree resolves in
// precedence order, and the client-safe projection excludes every secret
// structurally rather than by filtering.

const ENV_KEYS = ['ATOMI_LANDSCAPE', 'LANDSCAPE', 'BUILD_TIME_VARIABLES'] as const;
const saved = new Map<string, string | undefined>();

const setEnv = (key: string, value: string | undefined): void => {
  if (!saved.has(key)) saved.set(key, process.env[key]);
  if (value === undefined) delete process.env[key];
  else process.env[key] = value;
};

afterEach(() => {
  for (const key of ENV_KEYS) {
    if (!saved.has(key)) continue;
    const previous = saved.get(key);
    if (previous === undefined) delete process.env[key];
    else process.env[key] = previous;
  }
  saved.clear();
});

describe('serverLandscape', () => {
  it.each([
    { label: 'the ATOMI_ prefixed binding', env: { ATOMI_LANDSCAPE: 'lapras' }, expected: 'lapras' },
    { label: 'the bare LANDSCAPE binding', env: { LANDSCAPE: 'pichu' }, expected: 'pichu' },
    { label: 'nothing at all (prerender default)', env: {}, expected: 'base' },
  ])('should read the landscape from $label', async ({ env, expected }) => {
    // Arrange — the host supplies landscape; the accessor performs no detection.
    for (const key of ENV_KEYS) setEnv(key, undefined);
    for (const [key, value] of Object.entries(env)) setEnv(key, value);
    const { serverLandscape } = await import('../../src/adapters/server-config');

    // Act
    const actual = serverLandscape();

    // Assert
    should(actual).equal(expected);
  });

  it('should prefer the ATOMI_ prefixed binding when both are present', async () => {
    // Arrange
    setEnv('ATOMI_LANDSCAPE', 'lapras');
    setEnv('LANDSCAPE', 'pichu');
    const { serverLandscape } = await import('../../src/adapters/server-config');

    // Act
    const actual = serverLandscape();

    // Assert
    should(actual).equal('lapras');
  });
});

describe('serverConfig', () => {
  it('should load and validate the composed config tree', async () => {
    // Arrange
    for (const key of ENV_KEYS) setEnv(key, undefined);
    const { serverConfig } = await import('../../src/adapters/server-config');

    // Act
    const config = await serverConfig();

    // Assert
    should(config.get('app').servicetree.service).equal('nextjs-frontend');
    should(config.get('branding').appName).be.a.String().and.not.empty();
  });

  it('should memoize the load so a second call reuses the validated tree', async () => {
    // Arrange
    const { serverConfig } = await import('../../src/adapters/server-config');

    // Act
    const first = await serverConfig();
    const second = await serverConfig();

    // Assert — config is immutable for the life of the process/isolate.
    should(first).equal(second);
  });

  it('should ignore malformed build-time variables rather than failing the boot', async () => {
    // Arrange — a corrupt DefinePlugin payload must degrade, not crash. The parse
    // itself is pure (`src/lib/build-env`, unit-proven across every bad shape);
    // this proves the adapter routes the raw env through it.
    setEnv('BUILD_TIME_VARIABLES', '{not json');
    const { serverConfig } = await import('../../src/adapters/server-config');

    // Act
    const config: RootConfig = await serverConfig();

    // Assert
    should(config.get('app').servicetree.platform).equal('diene');
  });
});

describe('clientSafeConfig', () => {
  it('should carry the server-resolved landscape into the client payload', async () => {
    // Arrange
    const { clientSafeConfig } = await import('../../src/adapters/server-config');
    const config = await intConfig('base');

    // Act
    const projected = clientSafeConfig(config, 'lapras');

    // Assert — the payload's landscape is the one the server passed, not the baked block.
    should(projected.landscape).equal('lapras');
    should(projected.app.servicetree.landscape).equal('base');
  });

  it('should exclude every secret-bearing block from the client payload', async () => {
    // Arrange
    const { clientSafeConfig } = await import('../../src/adapters/server-config');
    const config = await intConfig('base');

    // Act
    const projected = clientSafeConfig(config, 'base') as unknown as Record<string, unknown>;

    // Assert — auth and otel never cross the boundary at all.
    should(projected['auth']).equal(undefined);
    should(projected['otel']).equal(undefined);
    should(Object.keys(projected.faro as object).sort()).deepEqual(['app', 'enabled', 'endpoint']);
  });

  it('should project each backend down to its base URL only', async () => {
    // Arrange — backend resource coordinates stay server-side.
    const { clientSafeConfig } = await import('../../src/adapters/server-config');
    const config = await intConfig('base');

    // Act
    const projected = clientSafeConfig(config, 'base');

    // Assert
    for (const backend of Object.values(projected.backends)) {
      should(Object.keys(backend)).deepEqual(['baseUrl']);
    }
  });
});
