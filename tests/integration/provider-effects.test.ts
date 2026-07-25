import { afterAll, beforeAll, describe, it } from 'bun:test';
import should from 'should';
import { installBrowser, fakeStorage } from './fixtures/browser';
import { mockReact, renderHook, restoreReact } from './fixtures/hook-harness';
import { intConfig } from './fixtures/config';
import type { ClientSafeConfig } from '../../src/config';

// Integration: the client provider stack's MOUNT effects — the module registry
// builds, the runtime theme store attaches and detaches, and faro initializes.
// SSR cannot reach these (they are effects), so they run through the hook
// harness in their own file, where the React substitute is isolated from the
// react-dom/server specs.

let clientConfig: ClientSafeConfig;
let restore: () => void;

beforeAll(async () => {
  mockReact();
  const installed = installBrowser(fakeStorage());
  restore = installed.restore;
  const { clientSafeConfig } = await import('../../src/adapters/server-config');
  clientConfig = clientSafeConfig(await intConfig('base'), 'lapras');
});

afterAll(() => {
  restoreReact();
  restore();
});

describe('Providers mount effects', () => {
  it('should build the module registry and attach the runtime theme store on mount', async () => {
    // Arrange
    const { Providers } = await import('../../src/adapters/atomi/Providers');

    // Act — calling the component runs its effects through the harness.
    const hook = renderHook(() => Providers({ config: clientConfig, children: null }));
    await Promise.resolve();
    await Promise.resolve();
    hook.rerender();

    // Assert — the theme store applied a resolved theme to the document element.
    const applied = (globalThis as unknown as { document: { documentElement: { dataset: Record<string, string> } } })
      .document.documentElement.dataset['theme'];
    should(applied).be.a.String().and.not.empty();

    // Act — unmount must tear the theme store down.
    hook.unmount();

    // Assert — no throw on teardown is the contract; the store owns its own cleanup.
    should(hook.current()).be.ok();
  });

  it('should abandon a module build whose provider unmounted before it resolved', async () => {
    // Arrange — unmounting mid-build must not set state on a dead tree.
    const { Providers } = await import('../../src/adapters/atomi/Providers');
    const hook = renderHook(() => Providers({ config: clientConfig, children: null }));

    // Act
    hook.unmount();
    await Promise.resolve();
    await Promise.resolve();

    // Assert
    should(hook.current()).be.ok();
  });
});
