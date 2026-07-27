import { afterAll, beforeAll, describe, it } from 'bun:test';
import should from 'should';
import { fakeStorage, installBrowser } from './fixtures/browser';
import { intConfig } from './fixtures/config';
import { mockReact, renderHook, restoreReact } from './fixtures/hook-harness';
import type { ClientSafeConfig } from '../../src/config';

// Integration: the browser storage ports DEGRADE, never throw. Safari private
// mode and cross-origin iframes make localStorage throw on access, so a theme
// switch and a form draft must both keep working — just unpersisted. This lives
// in its own file because the throwing storage has to be installed at import
// time, before the adapters capture their ports.

let clientConfig: ClientSafeConfig;
let restore: () => void;

beforeAll(async () => {
  mockReact();
  const installed = installBrowser(fakeStorage(true));
  restore = installed.restore;
  const { clientSafeConfig } = await import('../../src/adapters/server-config');
  clientConfig = clientSafeConfig(await intConfig('base'), 'base');
});

afterAll(() => {
  restoreReact();
  restore();
});

describe('theme storage port', () => {
  it('should still switch the theme when storage refuses both reads and writes', async () => {
    // Arrange — private mode: every localStorage access throws.
    const { createBrowserThemeStore } = await import('../../src/adapters/atomi/theme');

    // Act
    const store = createBrowserThemeStore(clientConfig.theme);
    store.setTheme('dark');

    // Assert — the switch lands on the document; only persistence is lost.
    should(store.getResolved().appearance).equal('dark');
    should(
      (
        globalThis as unknown as { document: { documentElement: { classList: { has: (n: string) => boolean } } } }
      ).document.documentElement.classList.has('dark'),
    ).be.true();
    store.destroy();
  });
});

describe('form draft storage port', () => {
  it('should keep accepting typed values when storage refuses to persist them', async () => {
    // Arrange
    const { useFormDraft } = await import('../../src/adapters/hooks/useFormDraft');

    // Act
    const hook = renderHook(() => useFormDraft('degraded', { title: '' }));
    hook.current().setValues({ title: 'buy milk' });

    // Assert — the form is fully usable; nothing was restorable to begin with.
    should(hook.current().values.title).equal('buy milk');
    should(hook.current().restored).be.false();

    // Act — the terminal triggers must not throw either.
    hook.current().clear('cancel');

    // Assert
    should(hook.current().values.title).equal('');
  });
});
