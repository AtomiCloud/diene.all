import { describe, it } from 'bun:test';
import should from 'should';
import { begin, idleAction, isPending, settle } from '../../src/lib/async-action';

// The click-reaction guard: exactly one run in flight at a time, so a double
// click can never double-submit.

describe('idleAction', () => {
  it('should start not pending', () => {
    // Arrange

    // Act
    const actual = isPending(idleAction);

    // Assert
    should(actual).equal(false);
  });
});

describe('begin', () => {
  it('should admit the first run and become pending', () => {
    // Arrange
    const state = idleAction;

    // Act
    const actual = begin(state);

    // Assert
    should(actual.admitted).equal(true);
    should(isPending(actual.state)).equal(true);
  });

  it('should REFUSE a re-entrant run while one is in flight', () => {
    // Arrange
    const first = begin(idleAction);

    // Act
    const actual = begin(first.state);

    // Assert
    should(actual.admitted).equal(false);
    should(isPending(actual.state)).equal(true);
  });

  it('should leave the in-flight state untouched when refusing', () => {
    // Arrange
    const first = begin(idleAction);

    // Act
    const actual = begin(first.state);

    // Assert
    should(actual.state).equal(first.state);
  });
});

describe('settle', () => {
  it('should return to idle so the next click is admitted', () => {
    // Arrange
    const first = begin(idleAction);

    // Act
    const settled = settle(first.state);
    const actual = begin(settled);

    // Assert
    should(isPending(settled)).equal(false);
    should(actual.admitted).equal(true);
  });

  it('should be idempotent on an already idle state', () => {
    // Arrange
    const state = idleAction;

    // Act
    const actual = settle(state);

    // Assert
    should(isPending(actual)).equal(false);
  });
});
