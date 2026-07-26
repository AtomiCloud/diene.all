import type { Problem } from '@atomicloud/diene.problems';
import type { Temporal } from '@js-temporal/polyfill';
import type { AuthClock } from '../../src/lib/provider';
import { testAuthProblems } from '../support/auth-problems';

/**
 * A fully-registered problems bag for unit tests. Delegates to the shared
 * {@link testAuthProblems} helper because the published `diene.problems`
 * registry constrains ids in a way `registerAuthProblems` cannot satisfy here
 * (documented in `tests/support/auth-problems.ts`).
 */
export function authProblems() {
  return { problems: testAuthProblems() };
}

export function testProblem(detail = 'test failure', status = 500): Problem {
  return {
    type: 'https://errors.atomi.cloud/test',
    title: 'Test failure',
    status,
    detail,
    data: {},
  };
}

/** A deterministic {@link AuthClock} pinned to one instant; no real time is read. */
export class FakeClock implements AuthClock {
  #instant: Temporal.Instant;

  constructor(start: Temporal.Instant) {
    this.#instant = start;
  }

  now(): Temporal.Instant {
    return this.#instant;
  }

  /** Move the clock forward by a duration. */
  advance(duration: Temporal.Duration): void {
    this.#instant = this.#instant.add(duration);
  }
}

/** An {@link AuthClock} that yields each instant in order, then repeats the last. */
export function sequenceClock(instants: readonly Temporal.Instant[]): AuthClock {
  let index = 0;
  return {
    now: () => instants[Math.min(index++, instants.length - 1)] as Temporal.Instant,
  };
}
