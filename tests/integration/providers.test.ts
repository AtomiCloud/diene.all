import { afterAll, beforeAll, describe, it } from 'bun:test';
import should from 'should';
import { createElement, type ComponentType, type ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { installBrowser, fakeStorage } from './fixtures/browser';
import { intConfig } from './fixtures/config';

// createElement's children-in-props typing fights biome's noChildrenProp; a
// tiny JSX-free wrapper renders a provider with positional children instead.
const renderWith = <P extends object>(
  component: ComponentType<P & { children: ReactNode }>,
  props: P,
  child: ReactNode,
): string => renderToStaticMarkup(createElement(component as ComponentType<P>, props, child));

// Integration: the client provider stack and the modules/theme/faro adapters it
// wires. Rendering happens through react-dom/server (no browser needed), which
// is enough to prove the SSR payload reaches consumers and that the provider
// contract holds; interactive behaviour is the e2e tier's job.

let clientConfig: Awaited<ReturnType<typeof buildClientConfig>>;
let restore: () => void;

const buildClientConfig = async () => {
  const { clientSafeConfig } = await import('../../src/adapters/server-config');
  return clientSafeConfig(await intConfig('base'), 'lapras');
};

beforeAll(async () => {
  const installed = installBrowser(fakeStorage());
  restore = installed.restore;
  clientConfig = await buildClientConfig();
});

afterAll(() => {
  restore();
});

describe('ClientConfigProvider', () => {
  it('should hand the SSR-injected landscape to a consumer through context', async () => {
    // Arrange
    const { ClientConfigProvider, useLandscape } = await import('../../src/adapters/atomi/ClientConfigProvider');
    const Probe = () => createElement('span', null, useLandscape());

    // Act
    const html = renderWith(ClientConfigProvider, { config: clientConfig }, createElement(Probe, null));

    // Assert — the landscape the server resolved, not a client-detected one.
    should(html).containEql('lapras');
  });

  it('should expose the whole client-safe config to consumers', async () => {
    // Arrange
    const { ClientConfigProvider, useClientConfig } = await import('../../src/adapters/atomi/ClientConfigProvider');
    const Probe = () => createElement('span', null, useClientConfig().app.servicetree.service);

    // Act
    const html = renderWith(ClientConfigProvider, { config: clientConfig }, createElement(Probe, null));

    // Assert
    should(html).containEql('nextjs-frontend');
  });

  it('should refuse to serve config outside the provider rather than returning a default', async () => {
    // Arrange
    const { useClientConfig } = await import('../../src/adapters/atomi/ClientConfigProvider');
    const Probe = () => createElement('span', null, useClientConfig().landscape);

    // Act
    const render = () => renderToStaticMarkup(createElement(Probe));

    // Assert
    should(render).throw(/must be used inside ClientConfigProvider/);
  });
});

describe('Providers', () => {
  it('should render the provider stack and its children on the server pass', async () => {
    // Arrange
    const { Providers } = await import('../../src/adapters/atomi/Providers');

    // Act — SSR renders with the stand-in theme store; effects never run here.
    const html = renderWith(Providers, { config: clientConfig }, createElement('main', null, 'shell'));

    // Assert
    should(html).containEql('shell');
  });

  it('should report no resolved modules during the server pass', async () => {
    // Arrange — module registration is async, so SSR must render the loading branch.
    const { Providers, useModules } = await import('../../src/adapters/atomi/Providers');
    const Probe = () => createElement('span', null, useModules() === undefined ? 'pending' : 'resolved');

    // Act
    const html = renderWith(Providers, { config: clientConfig }, createElement(Probe, null));

    // Assert
    should(html).containEql('pending');
  });
});

describe('buildModules', () => {
  it('should resolve the problem-view registry and content-store factory from the registry', async () => {
    // Arrange
    const { buildModules } = await import('../../src/adapters/atomi/modules');

    // Act
    const modules = await buildModules(clientConfig);

    // Assert
    should(modules.registry).be.ok();
    should(modules.problemViews).be.ok();
    should(modules.createContentStore).be.a.Function();
  });

  it('should hand out an independent content store per call', async () => {
    // Arrange
    const { buildModules } = await import('../../src/adapters/atomi/modules');
    const modules = await buildModules(clientConfig);

    // Act
    const first = modules.createContentStore<{ id: string }>();
    const second = modules.createContentStore<{ id: string }>();

    // Assert — one store per content unit, never a shared singleton.
    should(first).not.equal(second);
    should(first.getState().status).equal('idle');
  });
});

describe('createBrowserThemeStore', () => {
  it('should resolve a theme through the browser ports and apply it to the document', async () => {
    // Arrange
    const { createBrowserThemeStore } = await import('../../src/adapters/atomi/theme');

    // Act
    const store = createBrowserThemeStore(clientConfig.theme);
    store.setTheme('dark');
    const resolved = store.getResolved();

    // Assert
    should(resolved.appearance).equal('dark');
    should(
      (
        globalThis as unknown as { document: { documentElement: { classList: { has: (n: string) => boolean } } } }
      ).document.documentElement.classList.has('dark'),
    ).be.true();
    store.destroy();
  });

  it('should persist the chosen preference through the storage port', async () => {
    // Arrange
    const { createBrowserThemeStore } = await import('../../src/adapters/atomi/theme');
    const store = createBrowserThemeStore(clientConfig.theme);

    // Act
    store.setTheme('light');

    // Assert
    const storage = (globalThis as unknown as { window: { localStorage: { getItem: (k: string) => string | null } } })
      .window.localStorage;
    should(storage.getItem(clientConfig.theme.storageKey)).equal('light');
    store.destroy();
  });
});

describe('initFaro', () => {
  it('should stay inert when faro is disabled in config', async () => {
    // Arrange — the shipped base config has faro disabled.
    const { initFaro, getFaro } = await import('../../src/adapters/atomi/faro');

    // Act
    const instance = initFaro(clientConfig);

    // Assert — no browser SDK is booted, and the accessor agrees.
    should(instance).equal(undefined);
    should(getFaro()).equal(undefined);
  });

  it('should boot the SDK once with the LPSM session attributes when enabled', async () => {
    // Arrange — substitute the browser SDK; a fresh module instance keeps the
    // adapter's init-once latch independent of the disabled-path spec above.
    const { mock } = await import('bun:test');
    const booted: unknown[] = [];
    const sessions: unknown[] = [];
    const instance = {
      api: {
        setSession: (session: unknown) => sessions.push(session),
        pushError: () => undefined,
      },
    };
    mock.module('@grafana/faro-web-sdk', () => ({
      initializeFaro: (options: unknown) => {
        booted.push(options);
        return instance;
      },
    }));
    mock.module('@grafana/faro-web-tracing', () => ({ TracingInstrumentation: class {} }));
    // A query suffix gives bun a fresh module instance; the specifier is built at
    // runtime because TypeScript resolves import specifiers without one.
    const fresh = `../../src/adapters/atomi/faro${'?enabled'}`;
    const { initFaro, getFaro } = (await import(fresh)) as typeof import('../../src/adapters/atomi/faro');
    const enabled = { ...clientConfig, faro: { ...clientConfig.faro, enabled: true, endpoint: 'https://faro.test' } };

    // Act — a second provider mount must not re-init.
    const first = initFaro(enabled);
    const second = initFaro(enabled);

    // Assert
    should(booted.length).equal(1);
    should(first).equal(second);
    should(getFaro()).equal(instance);
    should(sessions).deepEqual([
      {
        attributes: {
          landscape: 'lapras',
          platform: enabled.app.servicetree.platform,
          service: enabled.app.servicetree.service,
          module: enabled.app.servicetree.module,
        },
      },
    ]);
  });
});
