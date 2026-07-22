import { UnwrapError } from './error.ts';
import { Option } from './option.ts';
import { type ResultSerial, readResultWire } from './wire.ts';

/**
 * A value that is either {@link Ok} or {@link Err}.
 *
 * Unlike the Dart sibling — whose C0 contract pins the error channel to
 * `Problem` from `package:diene_problems` — this Bun node genericises the error
 * type `E`. `bun-problems` is a DAG sibling, not a parent, so depending on it
 * would be an illegal cross-sibling edge; parameterising `E` is also the
 * TS-canonical shape (neverthrow/fp-ts).
 */
export type Result<T, E> = Ok<T, E> | Err<T, E>;

/** Arms for {@link Result} folding. */
export interface ResultMatchArms<T, E, R> {
  ok(value: T): R;
  err(error: E): R;
}

/** Optional per-variant encoders for {@link Result.serial}. */
export interface ResultEncode<T, E> {
  ok?(value: T): unknown;
  err?(error: E): unknown;
}

/** Per-variant decoders for {@link Result.fromSerial}. */
export interface ResultDecode<T, E> {
  ok(value: unknown): T;
  err?(error: unknown): E;
}

abstract class ResultBase<T, E> {
  /** Discriminant tag; `'ok'` or `'err'` for a well-formed value. */
  abstract readonly kind: 'ok' | 'err';

  protected constructor() {
    /* sealed hierarchy: instances are created only via Ok/Err */
  }

  /** Whether this result holds an {@link Ok} value. */
  get isOk(): boolean {
    return this.kind === 'ok';
  }

  /** Whether this result holds an {@link Err} error. */
  get isErr(): boolean {
    return this.kind === 'err';
  }

  /**
   * Folds both variants into one return type — the single dispatch point.
   *
   * A value whose tag is neither `'ok'` nor `'err'` (an invalid/uninitialised
   * result) throws {@link UnwrapError} here rather than returning silently.
   */
  match<R>(arms: ResultMatchArms<T, E, R>): R {
    if (this.kind === 'ok') {
      return arms.ok((this as unknown as Ok<T, E>).value);
    }
    if (this.kind === 'err') {
      return arms.err((this as unknown as Err<T, E>).error);
    }
    throw new UnwrapError({
      monad: 'result',
      expected: 'Ok or Err',
      actual: String((this as { kind: unknown }).kind),
    });
  }

  /** Transforms an {@link Ok} value and leaves an {@link Err} untouched. */
  map<R>(fn: (value: T) => R): Result<R, E> {
    return this.match<Result<R, E>>({
      ok: value => Result.ok(fn(value)),
      err: error => Result.err(error),
    });
  }

  /** Transforms an {@link Err} error and leaves an {@link Ok} untouched. */
  mapErr<F>(fn: (error: E) => F): Result<T, F> {
    return this.match<Result<T, F>>({
      ok: value => Result.ok(value),
      err: error => Result.err(fn(error)),
    });
  }

  /** Chains another fallible operation after an {@link Ok} value. */
  andThen<R>(fn: (value: T) => Result<R, E>): Result<R, E> {
    return this.match<Result<R, E>>({
      ok: value => fn(value),
      err: error => Result.err(error),
    });
  }

  /** Runs an {@link Ok}-side effect without capturing exceptions. */
  run(fn: (value: T) => void): Result<T, E> {
    this.match<void>({
      ok: value => fn(value),
      err: () => undefined,
    });
    return this as unknown as Result<T, E>;
  }

  /**
   * Runs an {@link Ok}-side effect, poisoning the chain on failure: a thrown
   * object is mapped to an {@link Err} via `onException`.
   */
  exec(fn: (value: T) => void, onException: (error: unknown) => E): Result<T, E> {
    return this.match<Result<T, E>>({
      ok: value => {
        try {
          fn(value);
          return this as unknown as Result<T, E>;
        } catch (error) {
          return Result.err(onException(error));
        }
      },
      err: () => this as unknown as Result<T, E>,
    });
  }

  /** Returns the {@link Ok} value or throws {@link UnwrapError}. */
  unwrap(): T {
    return this.match<T>({
      ok: value => value,
      err: error => {
        throw new UnwrapError({ monad: 'result', expected: 'Ok', actual: 'Err', payload: error });
      },
    });
  }

  /** Returns the {@link Err} error or throws {@link UnwrapError}. */
  unwrapErr(): E {
    return this.match<E>({
      ok: value => {
        throw new UnwrapError({ monad: 'result', expected: 'Err', actual: 'Ok', payload: value });
      },
      err: error => error,
    });
  }

  /** Returns the {@link Ok} value, or `fallback` for an {@link Err}. */
  unwrapOr(fallback: T): T {
    return this.match<T>({ ok: value => value, err: () => fallback });
  }

  /** Returns the {@link Ok} value, or computes a fallback from the error. */
  unwrapOrElse(fn: (error: E) => T): T {
    return this.match<T>({ ok: value => value, err: error => fn(error) });
  }

  /** Projects the {@link Ok} channel into an {@link Option}. */
  ok(): Option<T> {
    return this.match<Option<T>>({ ok: value => Option.some(value), err: () => Option.none() });
  }

  /** Projects the {@link Err} channel into an {@link Option}. */
  err(): Option<E> {
    return this.match<Option<E>>({ ok: () => Option.none(), err: error => Option.some(error) });
  }

  /** Returns the payload of whichever variant is present. */
  native(): T | E {
    return this.match<T | E>({ ok: value => value, err: error => error });
  }

  /** Encodes this result using the tagged-object wire contract. */
  serial(encode?: ResultEncode<T, E>): ResultSerial {
    return this.match<ResultSerial>({
      ok: value => ({ kind: 'ok', value: encode?.ok ? encode.ok(value) : value }),
      err: error => ({ kind: 'err', error: encode?.err ? encode.err(error) : error }),
    });
  }
}

/** The successful {@link Result} variant. */
export class Ok<T, E = never> extends ResultBase<T, E> {
  readonly kind = 'ok' as const;
  readonly value: T;

  constructor(value: T) {
    super();
    this.value = value;
  }
}

/** The failed {@link Result} variant. */
export class Err<T, E> extends ResultBase<T, E> {
  readonly kind = 'err' as const;
  readonly error: E;

  constructor(error: E) {
    super();
    this.error = error;
  }
}

/** Constructors and wire decoder for {@link Result} (const companion). */
export const Result = {
  /** Creates an {@link Ok} result. */
  ok<T, E = never>(value: T): Result<T, E> {
    return new Ok<T, E>(value);
  },

  /** Creates an {@link Err} result. */
  err<E, T = never>(error: E): Result<T, E> {
    return new Err<T, E>(error);
  },

  /** Decodes the `{kind:'ok',value} | {kind:'err',error}` wire form. */
  fromSerial<T, E>(serial: ResultSerial, decode: ResultDecode<T, E>): Result<T, E> {
    const wire = readResultWire(serial);
    if (wire.kind === 'ok') {
      return Result.ok(decode.ok(wire.value));
    }
    const decodeErr = decode.err ?? ((error: unknown) => error as E);
    return Result.err(decodeErr(wire.error));
  },
} as const;

/** Async-aware counterpart of {@link ResultBase.map} over `Promise<Result>`. */
export async function mapAsync<T, E, R>(
  promise: Promise<Result<T, E>>,
  fn: (value: T) => R | Promise<R>,
): Promise<Result<R, E>> {
  const result = await promise;
  return result.isOk ? Result.ok(await fn(result.unwrap())) : Result.err(result.unwrapErr());
}

/** Async-aware counterpart of {@link ResultBase.mapErr} over `Promise<Result>`. */
export async function mapErrAsync<T, E, F>(
  promise: Promise<Result<T, E>>,
  fn: (error: E) => F | Promise<F>,
): Promise<Result<T, F>> {
  const result = await promise;
  return result.isErr ? Result.err(await fn(result.unwrapErr())) : Result.ok(result.unwrap());
}

/** Async-aware counterpart of {@link ResultBase.andThen} over `Promise<Result>`. */
export async function andThenAsync<T, E, R>(
  promise: Promise<Result<T, E>>,
  fn: (value: T) => Result<R, E> | Promise<Result<R, E>>,
): Promise<Result<R, E>> {
  const result = await promise;
  return result.isOk ? await fn(result.unwrap()) : Result.err(result.unwrapErr());
}

/** Async-aware counterpart of {@link ResultBase.match} over `Promise<Result>`. */
export async function matchAsync<T, E, R>(
  promise: Promise<Result<T, E>>,
  arms: { ok(value: T): R | Promise<R>; err(error: E): R | Promise<R> },
): Promise<R> {
  const result = await promise;
  return result.isOk ? await arms.ok(result.unwrap()) : await arms.err(result.unwrapErr());
}

/** Awaits the result and unwraps its {@link Ok} value. */
export async function unwrapAsync<T, E>(promise: Promise<Result<T, E>>): Promise<T> {
  return (await promise).unwrap();
}

/** Awaits the result and unwraps its {@link Err} error. */
export async function unwrapErrAsync<T, E>(promise: Promise<Result<T, E>>): Promise<E> {
  return (await promise).unwrapErr();
}
