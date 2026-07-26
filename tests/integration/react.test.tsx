// Register a happy-dom environment BEFORE React / react-dom are imported.
// The native (Bun) console is preserved: happy-dom's console.timeStamp throws,
// which React 19's dev build calls during rendering.
import { GlobalWindow } from 'happy-dom';

const happyWindow = new GlobalWindow({ url: 'https://localhost/' });
{
  const target = globalThis as unknown as Record<string, unknown>;
  const source = happyWindow as unknown as Record<string, unknown>;
  const names = new Set<string>();
  let cursor: object | null = happyWindow;
  while (cursor) {
    for (const name of Object.getOwnPropertyNames(cursor)) names.add(name);
    cursor = Object.getPrototypeOf(cursor);
  }
  for (const name of names) {
    if (name === 'globalThis' || name === 'undefined' || name === 'console') continue;
    try {
      target[name] = source[name];
    } catch {
      /* read-only global — ignore */
    }
  }
  target.window = happyWindow;
  target.self = happyWindow;
  target.document = happyWindow.document;
  target.navigator = happyWindow.navigator;
  target.location = happyWindow.location;
}

import type { Problem } from '@atomicloud/diene.problems';
import { afterEach, describe, it } from 'bun:test';
import * as React from 'react';
import { flushSync } from 'react-dom';
import { createRoot, type Root } from 'react-dom/client';
import should from 'should';
import { createContentStore, createProblemViewRegistry } from '../../src/lib/content/index';
import {
  type Appearance,
  createThemeStore,
  type SystemAppearancePort,
  type ThemeApplierPort,
  type ThemeStoragePort,
} from '../../src/lib/theme/index';
import { Content, ProblemView, renderContentState } from '../../src/react/content';
import { ThemeProvider, useTheme } from '../../src/react/theme';

interface Mounted {
  readonly text: () => string;
  readonly unmount: () => void;
}

const roots: Root[] = [];

const mount = (node: React.ReactNode): Mounted => {
  const container = document.createElement('div');
  document.body.appendChild(container);
  const root = createRoot(container);
  roots.push(root);
  flushSync(() => root.render(node));
  return {
    text: () => container.textContent ?? '',
    unmount: () => {
      flushSync(() => root.unmount());
      container.remove();
    },
  };
};

/** Force React to flush any store-driven re-renders scheduled outside an event. */
const flush = (): void => {
  flushSync(() => {});
};

afterEach(() => {
  while (roots.length > 0) {
    const root = roots.pop();
    if (root) flushSync(() => root.unmount());
  }
});

const deferred = <T,>() => {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>(res => {
    resolve = res;
  });
  return { promise, resolve };
};

interface BoundaryProps {
  readonly children: React.ReactNode;
  readonly onError: (error: Error) => void;
}

class ErrorBoundary extends React.Component<BoundaryProps, { readonly failed: boolean }> {
  override state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  override componentDidCatch(error: Error) {
    this.props.onError(error);
  }
  override render() {
    return this.state.failed ? React.createElement('span', null, 'caught') : this.props.children;
  }
}

const branches = {
  idle: () => <span>idle</span>,
  loading: () => <span>loading…</span>,
  empty: (reason: string) => <span>empty:{reason}</span>,
  error: (problem: Problem) => <span>error:{problem.title}</span>,
  content: (data: string) => <span>data:{data}</span>,
};

describe('react/content · renderContentState (pure branches)', () => {
  it('should render the idle branch, or nothing when idle is omitted', () => {
    should(mount(<>{renderContentState({ status: 'idle' }, branches)}</>).text()).equal('idle');
    should(mount(<>{renderContentState({ status: 'idle' }, { ...branches, idle: undefined })}</>).text()).equal('');
  });

  it('should render loading, empty, error and content branches', () => {
    should(mount(<>{renderContentState({ status: 'loading' }, branches)}</>).text()).equal('loading…');
    should(mount(<>{renderContentState({ status: 'empty', reason: 'none' }, branches)}</>).text()).equal('empty:none');
    const problem: Problem = { type: 't', title: 'Boom', status: 500, data: {} };
    should(mount(<>{renderContentState({ status: 'error', problem }, branches)}</>).text()).equal('error:Boom');
    should(mount(<>{renderContentState({ status: 'content', data: 'hi' }, branches)}</>).text()).equal('data:hi');
  });
});

describe('react/content · Content component', () => {
  it('should subscribe and render loading then content across a load', async () => {
    // Arrange
    const store = createContentStore<string>();
    const view = mount(<Content store={store} {...branches} />);
    should(view.text()).equal('idle');

    // Act — a slow load shows the loading branch first
    const pending = deferred<string>();
    flushSync(() => {
      void store.load(() => pending.promise);
    });
    should(view.text()).equal('loading…');

    // Act — resolution flips to content
    pending.resolve('payload');
    await pending.promise;
    flush();

    // Assert
    should(view.text()).equal('data:payload');
  });

  it('should render the empty branch for empty resolutions', async () => {
    // Arrange
    const store = createContentStore<number[]>({ notFound: 'nothing' });
    const view = mount(<Content store={store} {...branches} content={() => <span>list</span>} />);

    // Act
    await store.load(() => []);
    flush();

    // Assert
    should(view.text()).equal('empty:nothing');
  });

  it('should render the error branch when the source throws', async () => {
    // Arrange
    const store = createContentStore<string>();
    const view = mount(<Content store={store} {...branches} />);

    // Act
    await store.load(() => {
      throw new Error('kaput');
    });
    flush();

    // Assert — LocalError title
    should(view.text()).equal('error:Local Error');
  });
});

describe('react/content · ProblemView', () => {
  it('should render via the registry with a fallback and a per-type override', () => {
    // Arrange
    const registry = createProblemViewRegistry<React.ReactNode>(p => <span>fallback:{p.type}</span>);
    registry.register('known', p => <span>known:{p.title}</span>);
    const unknown: Problem = { type: 'mystery', title: 'X', status: 400, data: {} };
    const known: Problem = { type: 'known', title: 'Yep', status: 400, data: {} };

    // Act & Assert
    should(mount(<ProblemView registry={registry} problem={unknown} />).text()).equal('fallback:mystery');
    should(mount(<ProblemView registry={registry} problem={known} />).text()).equal('known:Yep');
  });
});

const themeFixtures = () => {
  const stored = new Map<string, string>();
  const storage: ThemeStoragePort = {
    get: key => stored.get(key) ?? null,
    set: (key, value) => {
      stored.set(key, value);
    },
  };
  const system: SystemAppearancePort = { get: () => 'light' as Appearance, subscribe: () => () => {} };
  const applier: ThemeApplierPort = { apply: () => {} };
  return { storage, system, applier };
};

const ThemeProbe = () => {
  const { resolved, preference, isDark } = useTheme();
  return (
    <span>
      {preference}/{resolved.appearance}/{isDark ? 'dark' : 'light'}
    </span>
  );
};

describe('react/theme · useTheme', () => {
  it('should throw when used outside a ThemeProvider', () => {
    // Arrange
    let message = '';

    // Act
    mount(
      <ErrorBoundary onError={error => (message = error.message)}>
        <ThemeProbe />
      </ErrorBoundary>,
    );

    // Assert
    should(message).match(/ThemeProvider/);
  });

  it('should expose the resolved theme and dark flag, and react to switches', () => {
    // Arrange
    const fixtures = themeFixtures();
    const store = createThemeStore({
      config: { themes: { midnight: 'dark' } },
      storage: fixtures.storage,
      system: fixtures.system,
      applier: fixtures.applier,
    });
    const view = mount(
      <ThemeProvider store={store}>
        <ThemeProbe />
      </ThemeProvider>,
    );
    should(view.text()).equal('system/light/light');

    // Act — switch to a dark named theme (driven through the store)
    flushSync(() => store.setTheme('midnight'));

    // Assert
    should(view.text()).equal('midnight/dark/dark');
  });
});
