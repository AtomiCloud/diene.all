import type { Result } from './result.js';
import { KResult } from './result.js';
import { UnwrapError } from './error.js';

interface OptionMatch<T, U> {
  // Map the Some value to a standard type
  some: ((val: T) => U) | ((val: T) => Promise<U>);
  // Map the None value to a standard type
  none: (() => U) | (() => Promise<U>) | U | Promise<U>;
}

interface OptionResultMatch<T, U, E> {
  some: ((val: T) => Result<U, E>) | ((val: T) => Promise<Result<U, E>>);
  none: (() => Result<U, E>) | (() => Promise<Result<U, E>>) | Result<U, E> | Promise<Result<U, E>>;
}

type OptionSome<T extends Option<unknown>[]> = {
  [K in keyof T]: K extends number ? (T[K] extends Option<infer U> ? U : never) : never;
};

type OptionSerial<T> = ISome<T> | INone;

class Opt {
  // From Serial format of an option, convert it into an option type
  /**
   * @template T
   * @param input - serialized format of the option
   * @returns {Option<T>} option reconstructed from the serial format
   */
  static fromSerial<T>(input: OptionSerial<T> | Promise<OptionSerial<T>>): Option<T> {
    return new KOption<T>(Promise.resolve(input));
  }

  // takes in a value and returns a new option with a some value
  /**
   * @template T
   * @param input - value to wrap in an option
   * @returns {Option<T>} option with a some value
   */
  static fromNative<T>(input?: T | null | undefined) {
    if (input === null || input === undefined) {
      return None<T>();
    }
    return Some(input);
  }

  // takes in a list of options and returns a new option with a list of some values if all the results are some, and none if any are none
  /**
   * @template T
   * @param i - list of options
   */
  static all<T extends Option<unknown>[]>(...i: [...T]): Option<OptionSome<T>> {
    const closure = async (): Promise<Option<OptionSome<T>>> => {
      const some: OptionSome<T> = [] as OptionSome<T>;
      let none = 0;
      const r = i.map(async e => {
        const isSome = await e.isSome();
        if (isSome) {
          const ok = await e.unwrap();
          return ['some', ok];
        } else {
          return ['none', null];
        }
      });
      const a = await Promise.all(r);
      for (const [t, v] of a) {
        if (t === 'some') {
          some.push(v);
        } else {
          none++;
        }
      }

      if (none > 0) {
        return None<OptionSome<T>>();
      }
      return Some(some);
    };
    return Opt.fromAsync(closure());
  }

  // Resolve the promise of an option, Promise<Option<T>> to Option<T> without async/await
  /**
   * @template T
   * @param p - promise of an option to resolve
   * @returns {Option<T>} resolved option
   */
  static fromAsync<T>(p: Promise<Option<T>>): Option<T> {
    return new KOption<T>(
      (async () => {
        const r = await p;
        const isSome = await r.isSome();
        if (isSome) {
          const ok = await r.unwrap();
          return Promise.resolve(['some', ok]);
        }
        return Promise.resolve(['none', null]);
      })(),
    );
  }

  // Create an Option from an async function
  /**
   * @template T
   * @param fn - async function that returns an option
   * @returns {Option<T>} option from the async function
   */
  static async<T>(fn: () => Promise<Option<T>>): Option<T> {
    return Opt.fromAsync(fn());
  }
}

interface Option<T> {
  // Checks if the Option is Some
  /**
   * @returns {Promise<boolean>} if the option is Some
   */
  isSome(): Promise<boolean>;

  // Checks if the Option is None
  /**
   * @returns {Promise<boolean>} if the option is None
   */
  isNone(): Promise<boolean>;

  // Pattern Match and return a standard value by providing mapper functions for
  // Some or None
  /**
   * @template T, U
   * @param fn - some mapper function and none mapper function. Both mappers can
   * be both sync or async
   * @returns {Promise<U>} the standard value that both mapper maps to
   */
  match<U>(fn: OptionMatch<T, U>): Promise<U>;

  // Maps the underlying value to another value, if it is not None
  // Mapper function can be async or sync.
  /**
   * @template T, U
   * @param fn - mapper function to map the underlying value. Can be sync or async
   * @returns {Option<U>} Mapped Option
   */
  map<U>(fn: ((val: T) => U) | ((val: T) => Promise<U>)): Option<U>;

  // Execute the mapper function if it is not None and the mapper returns an Option.
  // Mapper function can be async or sync.
  /**
   * @template T,U
   * @param fn - mapper function that returns on Option. Can be async or sync.
   * @returns {Option<U>} Mapped Option
   */
  andThen<U>(fn: ((v: T) => Option<U>) | ((v: T) => Promise<Option<U>>)): Option<U>;

  // Removes the Option type and return the underlying value.
  // Throws an error if None was inside.
  /**
   * @template T
   * @throws {UnwrapError} In the event that it was attempting to unwrap None
   * @return {Promise<T>} The underlying value
   */
  unwrap(): Promise<T>;

  // Removes the Option type and return the underlying value, but if it resolves to
  // None, handle it by checking the argument passed in.
  // Argument can be a deferred (function) or immediate value, and can be sync
  // or async.
  /**
   * @template T
   * @param def - the value to return in case option returns to none. It can be immedate
   * value (literal) or it can be deferred (function that returns T). Both can be sync or
   * async
   * @return {Promise<T>} The underlying value
   */
  unwrapOr(def: T | Promise<T> | (() => T) | (() => Promise<T>)): Promise<T>;

  // Converts an option into an Err Result. User needs to provide the Ok
  // Result in case the option resolves to None
  /**
   * @template O, T
   * @param {O | Promise<O>} ok - Ok value in the event Option resolves to None
   * @return {Result<T,E>} - The option value as err result
   */
  asErr<O>(ok: O | Promise<O>): Result<O, T>;

  // Converts an option into an Ok Result. User needs to provide the Err
  // Result in case the option resolves to None
  /**
   * @template E, T
   * @param {E | Promise<E>} err - Error value in the event Option resolves to None
   * @return {Result<T,E>} - The option value as ok result
   */
  asOk<E>(err: E | Promise<E>): Result<T, E>;

  // Converts an option to a result, by mapping both None and Some to a
  // standard result type.
  /**
   * @template T, O, E
   * @param fn - the mapper functions for Some and None. All mapper functions
   * can be sync or async. Additionally, None accepts literal values instead
   * or mappers
   * @returns {Result<O,E>} Result derived from the Option
   */
  asResult<O, E>(fn: OptionResultMatch<T, O, E>): Result<O, E>;

  // Runs the function passed in but does not capture the return value.
  // Accepts both sync and async functions.
  // **Does not handle exceptions**
  /**
   * @template T
   * @param sideEffect - Side effect to execute. Can be sync or async
   * @returns {Option<T>} Original Option
   */
  run(sideEffect: ((t: T) => void) | ((t: T) => Promise<void>)): Option<T>;

  // Obtain the underlying value or native, which is the native version of Option
  native(): Promise<T | null>;

  // Return the native serializable format of the option type
  serial(): Promise<OptionSerial<T>>;
}

type ISome<T> = ['some', T];
type INone = ['none', null];

class KOption<T> implements Option<T> {
  value: Promise<OptionSerial<T>>;

  constructor(value: Promise<OptionSerial<T>>) {
    this.value = Promise.resolve(value);
  }

  async native(): Promise<T | null> {
    const [, v] = await this.value;
    return v;
  }

  async serial(): Promise<OptionSerial<T>> {
    return this.value;
  }

  andThen<U>(fn: ((v: T) => Option<U>) | ((v: T) => Promise<Option<U>>)): Option<U> {
    return new KOption<U>(
      (async () => {
        const [type, value] = await this.value;
        if (type === 'none') {
          return [type, value] as INone;
        } else {
          const mapped = await fn(value);
          const isSome = await mapped.isSome();
          if (isSome) {
            const v = await mapped.unwrap();
            return ['some', v] as ISome<U>;
          } else {
            return ['none', null] as INone;
          }
        }
      })(),
    );
  }

  asErr<O>(ok: Promise<O> | O): Result<O, T> {
    return new KResult<O, T>(
      (async () => {
        const [t, v] = await this.value;
        if (t === 'none') {
          const s = await ok;
          return ['ok', s];
        } else {
          return ['err', v];
        }
      })(),
    );
  }

  asOk<E>(err: Promise<E> | E): Result<T, E> {
    return new KResult<T, E>(
      (async () => {
        const [t, v] = await this.value;
        if (t === 'none') {
          const s = await err;
          return ['err', s];
        } else {
          return ['ok', v];
        }
      })(),
    );
  }

  asResult<O, E>(fn: OptionResultMatch<T, O, E>): Result<O, E> {
    return new KResult<number, E>(Promise.resolve(['ok', 0])).andThen(async (): Promise<Result<O, E>> => {
      const [t, v] = await this.value;
      return await (async () => {
        if (t === 'none') {
          if (typeof fn.none === 'function') {
            const f = fn.none;
            return Promise.resolve(f());
          } else {
            return Promise.resolve(fn.none);
          }
        } else {
          return fn.some(v);
        }
      })();
    });
  }

  async isNone(): Promise<boolean> {
    const [t] = await this.value;
    return t === 'none';
  }

  async isSome(): Promise<boolean> {
    const [t] = await this.value;
    return t === 'some';
  }

  map<U>(fn: ((val: T) => U) | ((val: T) => Promise<U>)): Option<U> {
    return new KOption<U>(
      (async () => {
        const [t, v] = await this.value;
        if (t === 'none') {
          return [t, v];
        } else {
          const fv = await fn(v);
          return [t, fv];
        }
      })(),
    );
  }

  async match<U>(fn: OptionMatch<T, U>): Promise<U> {
    const [t, v] = await this.value;
    if (t === 'some') {
      return Promise.resolve(fn.some(v));
    } else {
      if (typeof fn.none === 'function') {
        const f = fn.none as (() => U) | (() => Promise<U>);
        return Promise.resolve(f());
      } else {
        return Promise.resolve(fn.none);
      }
    }
  }

  run(sideEffect: ((t: T) => void) | ((t: T) => Promise<void>)): Option<T> {
    return new KOption(
      (async () => {
        const [t, v] = await this.value;
        if (t === 'none') {
          return [t, v];
        } else {
          await sideEffect(v);
          return [t, v];
        }
      })(),
    );
  }

  async unwrap(): Promise<T> {
    const [t, v] = await this.value;
    if (t === 'some') {
      return v;
    } else {
      throw new UnwrapError('Failed to unwrap', 'option', 'Expected Some got None');
    }
  }

  async unwrapOr(def: Promise<T> | (() => T) | (() => Promise<T>) | T): Promise<T> {
    const [t, v] = await this.value;
    if (t === 'some') {
      return v;
    } else {
      if (typeof def === 'function') {
        const f = def as (() => T) | (() => Promise<T>);
        return Promise.resolve(f());
      } else {
        return def;
      }
    }
  }
}

function Some<T>(v: T): Option<T> {
  return new KOption(Promise.resolve(['some', v]));
}

function None<T>(): Option<T> {
  return new KOption<T>(Promise.resolve(['none', null]));
}

export { KOption, Some, None, Opt };
export type { Option, OptionSerial, OptionMatch, OptionResultMatch, ISome, INone };
