import { UnwrapError } from './error.ts';
import { Result } from './result.ts';
import { type OptionSerial, readOptionWire } from './wire.ts';

/** A value that is either {@link Some} or {@link None}. */
export type Option<T> = Some<T> | None<T>;

/** Arms for {@link Option} folding. */
export interface OptionMatchArms<T, R> {
  some(value: T): R;
  none(): R;
}

/** Arms for {@link OptionBase.asResult}. */
export interface OptionResultArms<T, R, E> {
  some(value: T): Result<R, E>;
  none(): Result<R, E>;
}

/** Optional encoder for {@link OptionBase.serial}. */
export interface OptionEncode<T> {
  some?(value: T): unknown;
}

/** Decoder for {@link Option.fromSerial}. */
export interface OptionDecode<T> {
  some(value: unknown): T;
}

abstract class OptionBase<T> {
  /** Discriminant tag; `'some'` or `'none'` for a well-formed value. */
  abstract readonly kind: 'some' | 'none';

  protected constructor() {
    /* sealed hierarchy: instances are created only via Some/None */
  }

  /** Whether this option contains a value. */
  get isSome(): boolean {
    return this.kind === 'some';
  }

  /** Whether this option is empty. */
  get isNone(): boolean {
    return this.kind === 'none';
  }

  /**
   * Folds both variants into one return type — the single dispatch point.
   *
   * A value whose tag is neither `'some'` nor `'none'` throws
   * {@link UnwrapError} here rather than returning silently.
   */
  match<R>(arms: OptionMatchArms<T, R>): R {
    if (this.kind === 'some') {
      return arms.some((this as unknown as Some<T>).value);
    }
    if (this.kind === 'none') {
      return arms.none();
    }
    throw new UnwrapError({
      monad: 'option',
      expected: 'Some or None',
      actual: String((this as { kind: unknown }).kind),
    });
  }

  /** Transforms a {@link Some} value and leaves {@link None} untouched. */
  map<R>(fn: (value: T) => R): Option<R> {
    return this.match<Option<R>>({
      some: value => Option.some(fn(value)),
      none: () => Option.none(),
    });
  }

  /** Chains another optional operation after a {@link Some} value. */
  andThen<R>(fn: (value: T) => Option<R>): Option<R> {
    return this.match<Option<R>>({ some: value => fn(value), none: () => Option.none() });
  }

  /** Returns the {@link Some} value or throws {@link UnwrapError}. */
  unwrap(): T {
    return this.match<T>({
      some: value => value,
      none: () => {
        throw new UnwrapError({ monad: 'option', expected: 'Some', actual: 'None' });
      },
    });
  }

  /** Returns the {@link Some} value, or `fallback` for {@link None}. */
  unwrapOr(fallback: T): T {
    return this.match<T>({ some: value => value, none: () => fallback });
  }

  /** Returns the {@link Some} value, or computes a fallback for {@link None}. */
  unwrapOrElse(fn: () => T): T {
    return this.match<T>({ some: value => value, none: () => fn() });
  }

  /** Converts {@link Some} to {@link Ok} and {@link None} to {@link Err}. */
  okOr<E>(error: E): Result<T, E> {
    return this.match<Result<T, E>>({
      some: value => Result.ok(value),
      none: () => Result.err(error),
    });
  }

  /** Maps either option variant directly into a {@link Result}. */
  asResult<R, E>(arms: OptionResultArms<T, R, E>): Result<R, E> {
    return this.match<Result<R, E>>({ some: value => arms.some(value), none: () => arms.none() });
  }

  /** Returns the nullable native representation (`undefined` for {@link None}). */
  native(): T | undefined {
    return this.match<T | undefined>({ some: value => value, none: () => undefined });
  }

  /** Encodes this option using the tagged-object wire contract. */
  serial(encode?: OptionEncode<T>): OptionSerial {
    return this.match<OptionSerial>({
      some: value => ({ kind: 'some', value: encode?.some ? encode.some(value) : value }),
      none: () => ({ kind: 'none' }),
    });
  }
}

/** The populated {@link Option} variant. */
export class Some<T> extends OptionBase<T> {
  readonly kind = 'some' as const;
  readonly value: T;

  constructor(value: T) {
    super();
    this.value = value;
  }
}

/** The empty {@link Option} variant. */
export class None<T> extends OptionBase<T> {
  readonly kind: 'none';

  constructor() {
    super();
    this.kind = 'none';
  }
}

/** Constructors and wire decoder for {@link Option} (const companion). */
export const Option = {
  /** Creates a {@link Some} option. */
  some<T>(value: T): Option<T> {
    return new Some<T>(value);
  },

  /** Creates a {@link None} option. */
  none<T>(): Option<T> {
    return new None<T>();
  },

  /** Converts `null`/`undefined` to {@link None} and every other value to {@link Some}. */
  fromNullable<T>(value: T | null | undefined): Option<T> {
    return value == null ? new None<T>() : new Some<T>(value);
  },

  /** Decodes the `{kind:'some',value} | {kind:'none'}` wire form. */
  fromSerial<T>(serial: OptionSerial, decode: OptionDecode<T>): Option<T> {
    const wire = readOptionWire(serial);
    return wire.kind === 'some' ? Option.some(decode.some(wire.value)) : Option.none();
  },
} as const;
