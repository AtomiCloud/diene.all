import { afterAll, beforeAll, describe, it, mock } from 'bun:test';
import should from 'should';
import { fakeStorage, installBrowser } from './fixtures/browser';
import { intConfig } from './fixtures/config';
import type { ClientSafeConfig } from '../../src/config';

// Integration: the DI wiring's failure guards. Module ids are unique by
// construction and buildModules registers exactly what it resolves, so both
// failure branches are unreachable through the real registry — they exist to
// surface a programming error loudly rather than hand back a half-built surface.
// Substituting the registry is the only way to prove they do that, so these
// specs live in their own file where the substitution stays file-scoped.

let clientConfig: ClientSafeConfig;

beforeAll(async () => {
  installBrowser(fakeStorage());
  const { clientSafeConfig } = await import('../../src/adapters/server-config');
  clientConfig = clientSafeConfig(await intConfig('base'), 'base');
});

const MODULE_PACKAGE = '@atomicloud/diene.frontend-utils/module';

// bun's module mocks outlive the file that installs them, so the substitute
// delegates to the real registry unless THIS file has armed a failure. A leak
// into a later file is then indistinguishable from the real package.
let failing: 'register' | 'resolve' | undefined;

beforeAll(async () => {
  const { Err } = await import('@atomicloud/diene.result');
  // Snapshot the real exports into plain values: a live namespace object would
  // resolve back through the mock once it is installed, recursing forever.
  const real = { ...(await import(MODULE_PACKAGE)) };
  const realCreate = real.createModuleRegistry as () => ReturnType<typeof real.createModuleRegistry>;
  mock.module(MODULE_PACKAGE, () => ({
    ...real,
    createModuleRegistry: () => {
      const registry = realCreate();
      return {
        ...registry,
        register: (module: { id: string }, config: unknown) =>
          failing === 'register'
            ? Err({ kind: 'duplicate-id', id: module.id })
            : registry.register(module as never, config as never),
        resolve: (id: string) => (failing === 'resolve' ? Err({ kind: 'missing-module', id }) : registry.resolve(id)),
      };
    },
  }));
});

afterAll(() => {
  failing = undefined;
});

describe('buildModules failure guards', () => {
  it('should throw naming the duplicate id when a module registers twice', async () => {
    // Arrange
    failing = 'register';
    const { buildModules } = await import('../../src/adapters/atomi/modules');

    // Act
    const outcome = await buildModules(clientConfig).then(
      () => 'built',
      (error: Error) => error.message,
    );

    // Assert — loud and specific; never a silently degraded registry.
    should(outcome).equal('module registration failed: duplicate-id (problem-views)');
  });

  it('should throw naming the missing id when a registered module cannot resolve', async () => {
    // Arrange
    failing = 'resolve';
    const { buildModules } = await import('../../src/adapters/atomi/modules');

    // Act
    const outcome = await buildModules(clientConfig).then(
      () => 'built',
      (error: Error) => error.message,
    );

    // Assert
    should(outcome).equal('module resolution failed: missing-module (problem-views)');
  });
});
