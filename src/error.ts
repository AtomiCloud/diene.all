/**
 * The error channel home for the Result/Option monads.
 *
 * `UnwrapError` is the only exception thrown by `unwrap`/`unwrapErr` when a
 * caller asks for the wrong variant, and it doubles as the three-state guard:
 * a value whose tag is neither the valid Ok/Err nor Some/None (an
 * invalid/uninitialised monad) surfaces the same error rather than silently
 * returning, mirroring dotnet's `InvalidResultException`.
 */

/** Identifies the monad that rejected an explicit unwrap operation. */
export type MonadKind = 'result' | 'option';

/** Constructor arguments for {@link UnwrapError}. */
export interface UnwrapErrorArgs {
  /** Monad whose variant was inspected. */
  readonly monad: MonadKind;
  /** Variant (or set of variants) requested by the caller. */
  readonly expected: string;
  /** Variant actually present. */
  readonly actual: string;
  /** Payload carried by the actual variant, when one exists. */
  readonly payload?: unknown;
}

/** Thrown when an explicit unwrap asks for the wrong (or an invalid) variant. */
export class UnwrapError extends Error {
  /** Monad whose variant was inspected. */
  readonly monad: MonadKind;
  /** Variant (or set of variants) requested by the caller. */
  readonly expected: string;
  /** Variant actually present. */
  readonly actual: string;
  /** Payload carried by the actual variant, when one exists. */
  readonly payload?: unknown;

  constructor(args: UnwrapErrorArgs) {
    super(`Expected ${args.expected}, got ${args.actual}.`);
    this.name = 'UnwrapError';
    this.monad = args.monad;
    this.expected = args.expected;
    this.actual = args.actual;
    this.payload = args.payload;
  }
}
