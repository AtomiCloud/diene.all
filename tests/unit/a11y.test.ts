import { describe, it } from 'bun:test';
import should from 'should';
import {
  animationDisableCss,
  createReducedMotionController,
  type MediaQueryPort,
  prefersReducedMotion,
  REDUCED_MOTION_QUERY,
  SAFE_AREA_SIDES,
  safeAreaInset,
  safeAreaPadding,
  safeAreaVars,
} from '../../src/lib/a11y/index';

const fakeMediaQuery = (initial: boolean) => {
  let matches = initial;
  const listeners = new Set<(m: boolean) => void>();
  const port: MediaQueryPort = {
    matches: () => matches,
    subscribe: listener => {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
  };
  const emit = (next: boolean) => {
    matches = next;
    for (const listener of listeners) listener(next);
  };
  return { port, emit, listenerCount: () => listeners.size };
};

describe('a11y · safe-area', () => {
  it('should expose the env() expression per side, with and without a fallback', () => {
    should(safeAreaInset('top')).equal('env(safe-area-inset-top)');
    should(safeAreaInset('bottom', '0px')).equal('env(safe-area-inset-bottom, 0px)');
  });

  it('should build a custom-property map for every side', () => {
    // Act
    const vars = safeAreaVars();

    // Assert
    should(Object.keys(vars)).have.length(SAFE_AREA_SIDES.length);
    should(vars['--safe-area-inset-left']).equal('env(safe-area-inset-left)');
  });

  it('should build a prefixed map with a fallback', () => {
    should(safeAreaVars('--sa', '0px')['--sa-top']).equal('env(safe-area-inset-top, 0px)');
  });

  it('should build a padding shorthand in T R B L order', () => {
    should(safeAreaPadding()).equal(
      'env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)',
    );
    should(safeAreaPadding('0px')).containEql('env(safe-area-inset-top, 0px)');
  });
});

describe('a11y · reduced motion', () => {
  it('should expose the canonical query and a snapshot read', () => {
    should(REDUCED_MOTION_QUERY).equal('(prefers-reduced-motion: reduce)');
    should(prefersReducedMotion(fakeMediaQuery(true).port)).be.true();
  });

  it('should track changes and notify subscribers', () => {
    // Arrange
    const media = fakeMediaQuery(false);
    const controller = createReducedMotionController(media.port);
    const seen: boolean[] = [];
    controller.subscribe(v => seen.push(v));

    // Act
    media.emit(true);

    // Assert
    should(controller.isReduced()).be.true();
    should(seen).deepEqual([true]);
  });

  it('should support unsubscribe and release the source on destroy', () => {
    // Arrange
    const media = fakeMediaQuery(false);
    const controller = createReducedMotionController(media.port);
    let notified = 0;
    const unsubscribe = controller.subscribe(() => {
      notified += 1;
    });

    // Act — unsubscribe one listener, then destroy
    unsubscribe();
    media.emit(true);
    controller.destroy();
    media.emit(false);

    // Assert
    should(notified).equal(0);
    should(media.listenerCount()).equal(0);
  });

  it('should build a mechanism-only animation-disable rule', () => {
    should(animationDisableCss()).startWith('*{');
    should(animationDisableCss('.motion')).startWith('.motion{');
    should(animationDisableCss()).containEql('animation-duration:0.01ms !important');
  });
});
