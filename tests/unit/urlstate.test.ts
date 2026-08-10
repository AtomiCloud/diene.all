import { describe, it } from 'bun:test';
import should from 'should';
import {
  computeNextSearch,
  createUrlStateController,
  DEFAULT_URLSTATE_DEBOUNCE_MS,
  type HistoryPort,
  readUrlState,
  serializeUrlState,
  type TimerHandle,
} from '../../src/lib/urlstate/index';

const makeClock = () => {
  let seq = 0;
  let now = 0;
  const tasks = new Map<number, { fn: () => void; at: number }>();
  const scheduler = {
    setTimer(fn: () => void, ms: number): TimerHandle {
      const id = ++seq;
      tasks.set(id, { fn, at: now + ms });
      return id;
    },
    clearTimer(handle: TimerHandle): void {
      tasks.delete(handle as number);
    },
  };
  const advance = (ms: number): void => {
    now += ms;
    for (const [id, task] of [...tasks]) {
      if (task.at <= now) {
        tasks.delete(id);
        task.fn();
      }
    }
  };
  return { scheduler, advance, pending: () => tasks.size };
};

const recordingHistory = () => {
  const searches: string[] = [];
  const port: HistoryPort = { replaceState: search => searches.push(search) };
  return { port, searches };
};

const defaults = { q: '', page: '1' };

describe('urlstate · readUrlState', () => {
  it('should read from a URLSearchParams source, keeping defaults for absent keys', () => {
    should(readUrlState(new URLSearchParams('q=hello'), defaults)).deepEqual({ q: 'hello', page: '1' });
  });

  it('should read from a query string source', () => {
    should(readUrlState('q=hi&page=3', defaults)).deepEqual({ q: 'hi', page: '3' });
  });

  it('should read from a Next-style record, taking the first of array values', () => {
    should(readUrlState({ q: ['a', 'b'], page: undefined }, defaults)).deepEqual({ q: 'a', page: '1' });
  });
});

describe('urlstate · serialize', () => {
  it('should omit values equal to their default', () => {
    should(serializeUrlState({ q: 'x', page: '1' }, defaults)).equal('q=x');
  });

  it('should skip keys absent from state', () => {
    // Arrange — state missing the `page` key entirely
    const partial = { q: 'x' } as unknown as typeof defaults;

    // Act & Assert
    should(serializeUrlState(partial, defaults)).equal('q=x');
  });

  it('should compute an empty search when nothing differs from defaults', () => {
    should(computeNextSearch({ q: '', page: '1' }, defaults)).equal('');
  });

  it('should prefix the search with ? when values differ', () => {
    should(computeNextSearch({ q: 'x', page: '2' }, defaults)).equal('?q=x&page=2');
  });
});

describe('urlstate · controller', () => {
  it('should merge defaults and initial state', () => {
    // Arrange
    const clock = makeClock();
    const history = recordingHistory();

    // Act
    const controller = createUrlStateController({
      defaults,
      initial: { q: 'seed' },
      history: history.port,
      scheduler: clock.scheduler,
    });

    // Assert
    should(controller.getState()).deepEqual({ q: 'seed', page: '1' });
  });

  it('should update local state immediately but debounce the replaceState into one write', () => {
    // Arrange
    const clock = makeClock();
    const history = recordingHistory();
    const controller = createUrlStateController({ defaults, history: history.port, scheduler: clock.scheduler });
    const seen: string[] = [];
    controller.subscribe(state => seen.push(state.q));

    // Act — rapid keystrokes
    controller.setState({ q: 'h' });
    controller.setState({ q: 'he' });
    controller.setState({ q: 'hey' });

    // Assert — local state and subscribers update immediately; URL not yet written
    should(controller.getState().q).equal('hey');
    should(seen).deepEqual(['h', 'he', 'hey']);
    should(history.searches).be.empty();

    // Act — debounce elapses
    clock.advance(DEFAULT_URLSTATE_DEBOUNCE_MS);

    // Assert — exactly one replaceState with the final value
    should(history.searches).deepEqual(['?q=hey']);
  });

  it('should sync synchronously when debounceMs is zero', () => {
    // Arrange
    const clock = makeClock();
    const history = recordingHistory();
    const controller = createUrlStateController({
      defaults,
      history: history.port,
      scheduler: clock.scheduler,
      debounceMs: 0,
    });

    // Act
    controller.setState({ q: 'now' });

    // Assert
    should(history.searches).deepEqual(['?q=now']);
  });

  it('should flush a pending write immediately', () => {
    // Arrange
    const clock = makeClock();
    const history = recordingHistory();
    const controller = createUrlStateController({ defaults, history: history.port, scheduler: clock.scheduler });

    // Act
    controller.setState({ q: 'flush-me' });
    controller.flush();

    // Assert
    should(history.searches).deepEqual(['?q=flush-me']);
    should(clock.pending()).equal(0);
  });

  it('should stop notifying after unsubscribe', () => {
    // Arrange
    const clock = makeClock();
    const history = recordingHistory();
    const controller = createUrlStateController({ defaults, history: history.port, scheduler: clock.scheduler });
    const seen: string[] = [];
    const unsubscribe = controller.subscribe(state => seen.push(state.q));

    // Act
    unsubscribe();
    controller.setState({ q: 'silent' });

    // Assert
    should(seen).be.empty();
    should(controller.getState().q).equal('silent');
  });

  it('should cancel a pending write and drop listeners on destroy', () => {
    // Arrange
    const clock = makeClock();
    const history = recordingHistory();
    const controller = createUrlStateController({ defaults, history: history.port, scheduler: clock.scheduler });

    // Act
    controller.setState({ q: 'dropped' });
    controller.destroy();
    clock.advance(DEFAULT_URLSTATE_DEBOUNCE_MS);

    // Assert
    should(history.searches).be.empty();
    should(clock.pending()).equal(0);
  });
});
