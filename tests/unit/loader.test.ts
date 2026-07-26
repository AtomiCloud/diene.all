import { describe, it } from 'bun:test';
import should from 'should';
import { CONTENT_DEBOUNCE_MS, createLoaderController, type TimerHandle } from '../../src/lib/loader/index';

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

describe('loader · content loader (debounced)', () => {
  it('should NOT show a spinner for a load that completes within the debounce window', () => {
    // Arrange
    const clock = makeClock();
    const loader = createLoaderController({ kind: 'content', scheduler: clock.scheduler });
    const seen: boolean[] = [];
    loader.subscribe(v => seen.push(v));

    // Act — start then stop before ~100ms elapses (fast load)
    loader.start();
    clock.advance(CONTENT_DEBOUNCE_MS - 1);
    loader.stop();
    clock.advance(CONTENT_DEBOUNCE_MS);

    // Assert — never became visible, so no flash
    should(loader.isVisible()).be.false();
    should(seen).be.empty();
  });

  it('should show a spinner once the debounce elapses for a slow load', () => {
    // Arrange
    const clock = makeClock();
    const loader = createLoaderController({ kind: 'content', scheduler: clock.scheduler, delayMs: 120 });
    const seen: boolean[] = [];
    loader.subscribe(v => seen.push(v));

    // Act
    loader.start();
    clock.advance(120);

    // Assert
    should(loader.isVisible()).be.true();
    should(seen).deepEqual([true]);

    // Act — stop hides it
    loader.stop();
    should(loader.isVisible()).be.false();
    should(seen).deepEqual([true, false]);
  });

  it('should coalesce repeated starts into a single scheduled timer', () => {
    // Arrange
    const clock = makeClock();
    const loader = createLoaderController({ kind: 'content', scheduler: clock.scheduler });

    // Act
    loader.start();
    loader.start();

    // Assert — the previous timer was cancelled, only one pending
    should(clock.pending()).equal(1);
  });
});

describe('loader · action loader (never debounced)', () => {
  it('should show a button spinner immediately regardless of delayMs', () => {
    // Arrange
    const clock = makeClock();
    const loader = createLoaderController({ kind: 'action', scheduler: clock.scheduler, delayMs: 500 });
    const seen: boolean[] = [];
    loader.subscribe(v => seen.push(v));

    // Act
    loader.start();

    // Assert — visible synchronously, no timer scheduled
    should(loader.isVisible()).be.true();
    should(clock.pending()).equal(0);
    should(seen).deepEqual([true]);
  });

  it('should not re-notify subscribers when visibility is unchanged', () => {
    // Arrange
    const clock = makeClock();
    const loader = createLoaderController({ kind: 'action', scheduler: clock.scheduler });
    const seen: boolean[] = [];
    loader.subscribe(v => seen.push(v));

    // Act
    loader.start();
    loader.start();

    // Assert
    should(seen).deepEqual([true]);
  });
});

describe('loader · lifecycle', () => {
  it('should cancel a pending timer and drop listeners on destroy', () => {
    // Arrange
    const clock = makeClock();
    const loader = createLoaderController({ kind: 'content', scheduler: clock.scheduler });
    let notified = 0;
    loader.subscribe(() => {
      notified += 1;
    });

    // Act
    loader.start();
    loader.destroy();
    clock.advance(CONTENT_DEBOUNCE_MS);

    // Assert
    should(loader.isVisible()).be.false();
    should(notified).equal(0);
    should(clock.pending()).equal(0);
  });

  it('should support unsubscribe', () => {
    // Arrange
    const clock = makeClock();
    const loader = createLoaderController({ kind: 'action', scheduler: clock.scheduler });
    const seen: boolean[] = [];
    const unsubscribe = loader.subscribe(v => seen.push(v));

    // Act
    unsubscribe();
    loader.start();

    // Assert
    should(seen).be.empty();
    should(loader.isVisible()).be.true();
  });
});
