import { describe, it } from 'bun:test';
import should from 'should';
import {
  assertPassiveSeverity,
  createToastStore,
  MIN_TOAST_DWELL_MS,
  PASSIVE_SEVERITIES,
  type TimerHandle,
  type Toast,
} from '../../src/lib/toast/index';

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

describe('toast · passive severity guard', () => {
  it('should accept every passive severity', () => {
    for (const severity of PASSIVE_SEVERITIES) should(() => assertPassiveSeverity(severity)).not.throw();
  });

  it('should reject error/assertive misuse', () => {
    should(() => assertPassiveSeverity('error')).throw(/not passive/);
  });
});

describe('toast · store', () => {
  it('should show a polite toast with a clamped minimum dwell', () => {
    // Arrange
    const clock = makeClock();
    const store = createToastStore({ scheduler: clock.scheduler });
    const seen: readonly Toast[][] = [];
    store.subscribe(toasts => (seen as Toast[][]).push([...toasts]));

    // Act — request less than the minimum dwell
    const toast = store.show({ message: 'Saved', severity: 'success', durationMs: 1000 });

    // Assert
    should(toast.ariaLive).equal('polite');
    should(toast.severity).equal('success');
    should(toast.durationMs).equal(MIN_TOAST_DWELL_MS);
    should(store.getToasts()).have.length(1);
    should(seen).have.length(1);
  });

  it('should default severity to info and honour a longer requested dwell', () => {
    // Arrange
    const clock = makeClock();
    const store = createToastStore({ scheduler: clock.scheduler });

    // Act
    const toast = store.show({ message: 'Heads up', durationMs: 8000 });

    // Assert
    should(toast.severity).equal('info');
    should(toast.durationMs).equal(8000);
  });

  it('should auto-dismiss after the dwell elapses', () => {
    // Arrange
    const clock = makeClock();
    const store = createToastStore({ scheduler: clock.scheduler });
    store.show({ message: 'bye' });

    // Act
    clock.advance(MIN_TOAST_DWELL_MS);

    // Assert
    should(store.getToasts()).be.empty();
    should(clock.pending()).equal(0);
  });

  it('should dismiss a toast early and cancel its timer', () => {
    // Arrange
    const clock = makeClock();
    const store = createToastStore({ scheduler: clock.scheduler });
    const toast = store.show({ message: 'x' });

    // Act
    store.dismiss(toast.id);

    // Assert
    should(store.getToasts()).be.empty();
    should(clock.pending()).equal(0);
  });

  it('should ignore dismissal of an unknown id', () => {
    // Arrange
    const clock = makeClock();
    const store = createToastStore({ scheduler: clock.scheduler });
    let notifications = 0;
    store.subscribe(() => {
      notifications += 1;
    });
    store.show({ message: 'x' });

    // Act
    store.dismiss('nope');

    // Assert — only the show emitted, the no-op dismiss did not
    should(notifications).equal(1);
    should(store.getToasts()).have.length(1);
  });

  it('should stop notifying after unsubscribe', () => {
    // Arrange
    const clock = makeClock();
    const store = createToastStore({ scheduler: clock.scheduler });
    let notifications = 0;
    const unsubscribe = store.subscribe(() => {
      notifications += 1;
    });

    // Act
    unsubscribe();
    store.show({ message: 'x' });

    // Assert
    should(notifications).equal(0);
    should(store.getToasts()).have.length(1);
  });

  it('should use a custom deterministic id factory', () => {
    // Arrange
    const clock = makeClock();
    const store = createToastStore({ scheduler: clock.scheduler, idFactory: () => 'fixed' });

    // Act
    const toast = store.show({ message: 'x' });

    // Assert
    should(toast.id).equal('fixed');
  });

  it('should clear all timers, toasts and listeners on destroy', () => {
    // Arrange
    const clock = makeClock();
    const store = createToastStore({ scheduler: clock.scheduler });
    let notifications = 0;
    store.subscribe(() => {
      notifications += 1;
    });
    store.show({ message: 'a' });
    store.show({ message: 'b' });

    // Act
    store.destroy();

    // Assert
    should(store.getToasts()).be.empty();
    should(clock.pending()).equal(0);

    // A subsequent advance does nothing and no further notifications arrive
    const before = notifications;
    clock.advance(MIN_TOAST_DWELL_MS);
    should(notifications).equal(before);
  });
});
