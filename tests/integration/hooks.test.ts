import { afterAll, beforeAll, describe, it } from 'bun:test';
import should from 'should';
import { installBrowser, fakeStorage, type FakeStorage, type FakeWindow } from './fixtures/browser';
import { mockReact, renderHook } from './fixtures/hook-harness';

// Integration: the client hooks' wiring over the frontend-utils cores —
// re-entrancy refusal, draft persistence through the four clear triggers, and
// url-as-state read/write/popstate. The hooks' own code runs; the browser and
// React primitives are substituted.

let handles: FakeWindow;
let restore: () => void;
let storage: FakeStorage;

beforeAll(() => {
  mockReact();
  storage = fakeStorage();
  const installed = installBrowser(storage, '?filter=today');
  handles = installed.handles;
  restore = installed.restore;
});

afterAll(() => {
  restore();
});

describe('useAsyncAction', () => {
  it('should refuse a re-entrant trigger while the action is in flight', async () => {
    // Arrange
    const { useAsyncAction } = await import('../../src/adapters/hooks/useAsyncAction');
    let started = 0;
    let release: (() => void) | undefined;
    const action = async (): Promise<void> => {
      started += 1;
      await new Promise<void>(resolve => {
        release = resolve;
      });
    };
    const hook = renderHook(() => useAsyncAction(action));

    // Act — a second click lands while the first is pending.
    hook.current().run();
    hook.current().run();

    // Assert — exactly one invocation, and the trigger reports pending.
    should(started).equal(1);
    should(hook.current().pending).be.true();

    // Act — settle, then trigger again.
    release?.();
    await Promise.resolve();
    await Promise.resolve();
    hook.current().run();

    // Assert — the guard reopened after settling.
    should(started).equal(2);
  });
});

describe('useFormDraft', () => {
  it('should persist typed values under the namespaced draft key', async () => {
    // Arrange
    const { useFormDraft } = await import('../../src/adapters/hooks/useFormDraft');
    const hook = renderHook(() => useFormDraft('reminder', { title: '' }));

    // Act
    hook.current().setValues({ title: 'buy milk' });

    // Assert
    should(hook.current().values.title).equal('buy milk');
    should([...storage.map.keys()]).containEql('diene.draft.reminder');
  });

  it('should restore a persisted draft on mount and report it as restored', async () => {
    // Arrange — a draft left behind by a previous session.
    const { useFormDraft } = await import('../../src/adapters/hooks/useFormDraft');
    storage.map.set('diene.draft.restorable', JSON.stringify({ title: 'buy milk' }));

    // Act
    const hook = renderHook(() => useFormDraft('restorable', { title: '' }));

    // Assert
    should(hook.current().restored).be.true();
    should(hook.current().values.title).equal('buy milk');
  });

  it('should clear the draft on submit so the next mount starts clean', async () => {
    // Arrange
    const { useFormDraft } = await import('../../src/adapters/hooks/useFormDraft');
    const hook = renderHook(() => useFormDraft('reminder', { title: '' }));

    // Act
    hook.current().clear('submit');

    // Assert
    should(hook.current().values.title).equal('');
    should(hook.current().restored).be.false();
    should(storage.map.has('diene.draft.reminder')).be.false();
  });

  it('should ignore a blank persisted draft rather than offering a pointless restore', async () => {
    // Arrange
    const { useFormDraft } = await import('../../src/adapters/hooks/useFormDraft');
    storage.map.set('diene.draft.blank', JSON.stringify({ title: '   ' }));

    // Act
    const hook = renderHook(() => useFormDraft('blank', { title: '' }));

    // Assert
    should(hook.current().restored).be.false();
  });
});

describe('useUrlState', () => {
  it('should hydrate initial state from the live URL query', async () => {
    // Arrange
    const { useUrlState } = await import('../../src/adapters/hooks/useUrlState');

    // Act
    const hook = renderHook(() => useUrlState({ filter: 'all' }));

    // Assert
    should(hook.current()[0].filter).equal('today');
  });

  it('should write a patched value back to the URL through replaceState', async () => {
    // Arrange
    const { useUrlState } = await import('../../src/adapters/hooks/useUrlState');
    const hook = renderHook(() => useUrlState({ filter: 'all' }));

    // Act — the controller debounces through the injected scheduler.
    hook.current()[1]({ filter: 'week' });
    handles.flushTimers();

    // Assert
    should(hook.current()[0].filter).equal('week');
    should(handles.replaced.join(' ')).containEql('filter=week');
  });

  it('should restore state from the URL on a back/forward navigation', async () => {
    // Arrange
    const { useUrlState } = await import('../../src/adapters/hooks/useUrlState');
    const hook = renderHook(() => useUrlState({ filter: 'all' }));
    hook.current()[1]({ filter: 'week' });
    handles.flushTimers();

    // Act — the browser navigates back to the original query.
    (globalThis as unknown as { window: { location: { search: string } } }).window.location.search = '?filter=today';
    handles.emit('popstate');

    // Assert
    should(hook.current()[0].filter).equal('today');
  });

  it('should detach its listeners on unmount', async () => {
    // Arrange — count only this hook's subscription; earlier specs left theirs mounted.
    const { useUrlState } = await import('../../src/adapters/hooks/useUrlState');
    const before = handles.listeners.get('popstate')?.size ?? 0;
    const hook = renderHook(() => useUrlState({ filter: 'all' }));
    const mounted = handles.listeners.get('popstate')?.size ?? 0;

    // Act
    hook.unmount();

    // Assert — subscribed on mount, detached on unmount.
    should(mounted).equal(before + 1);
    should(handles.listeners.get('popstate')?.size ?? 0).equal(before);
  });
});
