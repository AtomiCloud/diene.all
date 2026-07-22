/**
 * Dependency-light, assert-the-asserter helpers for the `/test-helper` subpath.
 *
 * These import only the monad *types* — never a test framework and never the
 * runtime implementation — so a downstream suite can assert a variant and
 * receive its payload, or a `TestHelperFailure` with a clear diff on mismatch.
 */
import type { Option } from './option.ts';
import type { Result } from './result.ts';

/** Thrown by the `be*` helpers when the asserted variant is not present. */
export class TestHelperFailure extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'TestHelperFailure';
  }
}

function describe(value: unknown): string {
  return typeof value === 'string' ? value : String(value);
}

/** Asserts an {@link Ok} and returns its value, else throws {@link TestHelperFailure}. */
export function beOk<T, E>(actual: Result<T, E>): T {
  if (actual.isOk) {
    return actual.unwrap();
  }
  throw new TestHelperFailure(`Expected Ok, got Err carrying ${describe(actual.unwrapErr())}.`);
}

/** Asserts an {@link Err} and returns its error, else throws {@link TestHelperFailure}. */
export function beErr<T, E>(actual: Result<T, E>): E {
  if (actual.isErr) {
    return actual.unwrapErr();
  }
  throw new TestHelperFailure(`Expected Err, got Ok carrying ${describe(actual.unwrap())}.`);
}

/** Asserts a {@link Some} and returns its value, else throws {@link TestHelperFailure}. */
export function beSome<T>(actual: Option<T>): T {
  if (actual.isSome) {
    return actual.unwrap();
  }
  throw new TestHelperFailure('Expected Some, got None.');
}

/** Asserts a {@link None}, else throws {@link TestHelperFailure}. */
export function beNone<T>(actual: Option<T>): void {
  if (actual.isNone) {
    return;
  }
  throw new TestHelperFailure(`Expected None, got Some carrying ${describe(actual.unwrap())}.`);
}
