import { UnwrapError } from './error.js';
import type { INone, ISome, Option } from './option.js';
import { KOption } from './option.js';

type ResultSerial<T, E> = ['ok', T] | ['err', E];

// Creates a new instance of `Result` as the `err` variant.
/**
 * @template T,X
 * @param error - error to be converted to a Result
 * @returns {Result<T,X>} - new instance of `Result` as the `err` variant
 */
function Err<T, X>(error: X | Promise<X>): Result<T, X> {
  return new KResult<T, X>(
    (async () => {
      const err = await error;
      return ['err', err];
    })(),
  );
}

// Creates a new instance of `Result` as the `ok` variant.
/**
 * @template T,X
 * @param val - value to be converted to a Result
 * @returns {Result<T,X>} - new instance of `Result` as the `ok` variant
 */
function Ok<T, X = never>(val: T | Promise<T>): Result<T, X> {
  return new KResult<T, X>(
    (async () => {
      const v = await val;
      return ['ok', v];
    })(),
  );
}

interface ResultMatch<T, E, U> {
  ok: ((val: T) => Promise<U>) | ((val: T) => U);
  err: ((val: E) => Promise<U>) | ((val: E) => U);
}

type ResultErr<T extends Result<unknown, unknown>[]> = T extends Array<Result<unknown, infer E>> ? E[] : never;

type ResultOk<T extends Result<unknown, unknown>[]> = {
  [K in keyof T]: K extends number ? (T[K] extends Result<infer U, unknown> ? U : never) : never;
};

class Res {
  // From Serial format of a result, convert it into a result type
  /**
   * @template T,E
   * @param a - serialized format of the result
   * @return {Result<T,E>} - new instance of `Result` by deserializing the serial format
   */
  static fromSerial<T, E>(a: ResultSerial<T, E> | Promise<ResultSerial<T, E>>): Result<T, E> {
    const p = Promise.resolve(a) satisfies Promise<ResultSerial<T, E>>;
    return new KResult<T, E>(p);
  }

  // Resolve the promise of a result, Promise<Result<T, E>> to Result<T,E> without async/await
  /**
   * @template T,E
   * @param p - promise of a result to resolve
   * @returns {Result<T,E>} - resolved result
   */
  static fromAsync<T, E>(p: Promise<Result<T, E>>): Result<T, E> {
    return new KResult<T, E>(
      (async () => {
        const r = await p;
        const isOk = await r.isOk();
        if (isOk) {
          const ok = await r.unwrap();
          return Promise.resolve(['ok', ok]);
        } else {
          const err = await r.unwrapErr();
          return Promise.resolve(['err', err]);
        }
      })(),
    );
  }

  // Create a Result from async function
  /**
   * @template T,E
   * @param fn - function that results in a Result, asynchronous
   * @returns {Result<T,E>} - resolved result
   */
  static async<T, E>(fn: () => Promise<Result<T, E>>): Result<T, E> {
    return Res.fromAsync(fn());
  }

  // takes in a list of results and returns a new result with a list of ok values if all results are ok or a list of error values if at least one result is an error
  /**
   * @template
   * @param i - list of results
   */
  static all<T extends Result<unknown, unknown>[]>(...i: [...T]): Result<ResultOk<T>, ResultErr<T>> {
    const closure = async (): Promise<Result<ResultOk<T>, ResultErr<T>>> => {
      const ok: ResultOk<T> = [] as unknown as ResultOk<T>;
      const err: ResultErr<T> = [] as unknown as ResultErr<T>;
      const r = i.map(async e => {
        const isOk = await e.isOk();
        if (isOk) {
          const okR = await e.unwrap();
          return ['ok', okR] as ['ok', ResultOk<T>[number]];
        } else {
          const errR = await e.unwrapErr();
          return ['err', errR] as ['err', ResultErr<T>[number]];
        }
      });
      const a = await Promise.all(r);
      for (const [t, v] of a) {
        if (t === 'ok') {
          ok.push(v);
        } else {
          err.push(v);
        }
      }
      if (err.length > 0) {
        return Err(err);
      }
      return Ok(ok);
    };
    return Res.fromAsync(closure());
  }
}

interface Result<T, E> {
  // returns a Promise of a boolean indicating whether the variant of the Result is "ok"
  /**
   * @returns {Promise<boolean>} - boolean indicating whether the variant of the Result is "ok"
   */
  isOk(): Promise<boolean>;

  // returns a Promise of a boolean indicating whether the variant of the Result is "err"
  /**
   * @returns {Promise<boolean>} - boolean indicating whether the variant of the Result is "err"
   */
  isErr(): Promise<boolean>;

  /**
   * @template T
   * @returns {Promise<T>} - promise of the unwrapped value
   * @throws {UnwrapError} - if the variant of the Result is "err"
   */
  // returns a Promise of the value of the Result if its variant is "ok". If its variant is "err", it throws an error.
  unwrap(): Promise<T>;

  // returns a Promise of the value of the Result if its variant is "ok", otherwise it returns the provided default value.
  /**
   * @template T
   * @param i - default value to be returned if the variant of the Result is "err". It can be the default value, promised value, or function that returns the default value or async function that returns the default value
   * @returns {Promise<T>} - promise of the unwrapped value
   */
  unwrapOr(i: T | Promise<T> | ((err: E) => Promise<T>) | ((err: E) => T)): Promise<T>;

  // returns a Promise of the error value of the Result if its variant is "err". If its variant is "ok", it throws an error
  /**
   * @template E
   * @returns {Promise<E>} - promise of the unwrapped error value
   * @throws {UnwrapError} - if the variant of the Result is "ok"
   */
  unwrapErr(): Promise<E>;

  // applies a mapper function to the value of the Result if its variant is "ok" and returns a new Result with the mapped value. If its variant is "err", it returns the original Result.
  /**
   * @template Y, E
   * @param mapper - function to map the value of the Result. mapper can be async.
   * @returns {Result<Y,E>} - new Result with the mapped value
   */
  map<Y>(mapper: ((a: T) => Promise<Y>) | ((a: T) => Y)): Result<Y, E>;

  // applies a mapper function to the error value of the Result if its variant is "err" and returns a new Result with the mapped error value. If its variant is "ok", it returns the original Result.
  /**
   * @template Y, T
   * @param mapper - function to map the error value of the Result. mapper can be async.
   * @returns {Result<T,Y>} - new Result with the mapped error value
   */
  mapErr<Y>(mapper: ((a: E) => Promise<Y>) | ((a: E) => Y)): Result<T, Y>;

  // returns a Promise of the value or error of the Result regardless of its variant.
  /**
   * @template T, E
   * @returns {Promise<T | E>} - promise of the value or error of the Result
   */
  native(): Promise<T | E>;

  // returns native serializable format of the result type
  /**
   * @template T, E
   * @returns {Promise<Promise<['err', E] | ['ok', T]>>} - promise of the native serializable format of the result type
   */
  serial(): Promise<ResultSerial<T, E>>;

  // method that takes in a function fn with ok and err cases. It applies the corresponding case based on the variant of the Result and returns the result of that case as a Promise.
  /**
   * @template U
   * @param fn - function with ok and err cases
   * @returns {Promise<U>} - promise of the result of the corresponding case
   */
  match<U>(fn: ResultMatch<T, E, U>): Promise<U>;

  // Takes in a function that maps the ok value of the Result to a new Result, if the Result is ok.
  // Returns the new Result that was mapped from the original Result.
  // If the Result is an error, the function is not called, and the original error Result is returned.
  /**
   * @template U
   * @param fn - function that maps the ok value of the Result to a new Result. fn can be async.
   * @returns {Result<U,E>} - new Result that was mapped from the original Result
   */
  andThen<U>(fn: ((val: T) => Result<U, E>) | ((val: T) => Promise<Result<U, E>>)): Result<U, E>;

  // Runs the function passed in but does not capture the return value.
  // Accepts both sync and async functions.
  // **Does not handle exceptions**
  /**
   * @template T
   * @param sideEffect - Side effect to execute. Can be sync or async
   * @returns {Result<T,E>} - original Result
   */
  run(sideEffect: ((t: T) => void) | ((t: T) => Promise<void>)): Result<T, E>;

  // Runs the function passed in but does not capture the return value.
  // Accepts both sync and async functions.
  // **Handles exceptions**
  /**
   * @template T
   * @param sideEffect  - Side effect to execute. Can be sync or async
   * @param mapper - function to map the error value of the Result. mapper can be async.
   * @returns {Result<T,E>} - original Result
   */
  exec(
    sideEffect: ((t: T) => void) | ((t: T) => Promise<void>),
    mapper?: (e: E) => Error | Promise<Error>,
  ): Result<T, Error>;

  // Returns an Option of the Ok result. Error will result in None
  /**
   * @template T
   * @returns {Option<T>} - Option of the Ok result
   */
  ok(): Option<T>;

  // Returns an Option of the Error result. Ok will result in None
  /**
   * @template E
   * @returns {Option<E>} - Option of the Error result
   */
  err(): Option<E>;
}

class KResult<T, X> implements Result<T, X> {
  value: Promise<ResultSerial<T, X>>;

  constructor(value: Promise<ResultSerial<T, X>>) {
    this.value = value;
  }

  andThen<U>(fn: ((val: T) => Result<U, X>) | ((val: T) => Promise<Result<U, X>>)): Result<U, X> {
    const wrapped = async () => {
      const [type, val] = await this.value;
      if (type === 'err') {
        return [type, val] as ['err', X];
      } else {
        const mapped = await fn(val);
        const mType = await mapped.isOk();
        if (mType) {
          const okVal = await Promise.resolve(mapped.unwrap());
          return ['ok', okVal] as ['ok', U];
        } else {
          const errVal = await Promise.resolve(mapped.unwrapErr());
          return ['err', errVal] as ['err', X];
        }
      }
    };
    return new KResult<U, X>(wrapped());
  }

  async isOk(): Promise<boolean> {
    const [type] = await this.value;
    return type === 'ok';
  }

  async isErr(): Promise<boolean> {
    const [type] = await this.value;
    return type === 'err';
  }

  async unwrap(): Promise<T> | never {
    const [type, val] = await this.value;
    if (type === 'ok') {
      return val;
    }
    throw new UnwrapError('Failed to unwrap', 'result', 'Expected Ok got Error');
  }

  async unwrapErr(): Promise<X> | never {
    const [type, val] = await this.value;
    if (type === 'err') {
      return val;
    }
    throw new UnwrapError('Failed to unwrap', 'result', 'Expected Err got Ok');
  }

  map<Y>(mapper: ((a: T) => Promise<Y>) | ((a: T) => Y)): Result<Y, X> {
    return new KResult<Y, X>(
      (async () => {
        const [type, val] = await this.value;
        if (type === 'ok') {
          const mapped: Y = await mapper(val);
          return ['ok', mapped] as ['ok', Y];
        } else {
          return ['err', val] as ['err', X];
        }
      })(),
    );
  }

  mapErr<Y>(mapper: ((a: X) => Promise<Y>) | ((a: X) => Y)): Result<T, Y> {
    return new KResult<T, Y>(
      (async () => {
        const [type, val] = await this.value;
        if (type === 'err') {
          const err = await mapper(val);
          return ['err', err] as ['err', Y];
        } else {
          return [type, val] as ['ok', T];
        }
      })(),
    );
  }

  async native(): Promise<T | X> {
    const [, val] = await this.value;
    return val;
  }

  async match<U>(fn: ResultMatch<T, X, U>): Promise<U> {
    const [type, val] = await this.value;
    if (type === 'ok') {
      return Promise.resolve(fn.ok(val));
    } else {
      return Promise.resolve(fn.err(val));
    }
  }

  async unwrapOr(i: Promise<T> | ((err: X) => Promise<T>) | ((err: X) => T) | T): Promise<T> {
    const [type, val] = await this.value;
    if (type === 'ok') {
      return val;
    } else {
      if (typeof i === 'function') {
        const f = i as ((err: X) => Promise<T>) | ((err: X) => T);
        return f(val);
      } else {
        return Promise.resolve(i);
      }
    }
  }

  err(): Option<X> {
    const closure = async (): Promise<ISome<X> | INone> => {
      const [t, v] = await this.value;
      if (t === 'err') {
        return ['some', v] as ['some', X];
      } else {
        return ['none', null] as ['none', null];
      }
    };
    return new KOption<X>(closure());
  }

  exec(
    sideEffect: ((t: T) => void) | ((t: T) => Promise<void>),
    mapper: (e: X) => Error | Promise<Error> = (e: X) => {
      if (e instanceof Error) {
        return Promise.resolve(e);
      } else {
        return Promise.resolve(new Error(JSON.stringify(e)));
      }
    },
  ): Result<T, Error> {
    const closure = async () => {
      const [t, v] = await this.value;
      if (t === 'err') {
        const err = await mapper(v);
        return [t, err] as ['err', Error];
      } else {
        try {
          await sideEffect(v);
        } catch (e) {
          if (e instanceof Error) {
            return ['err', e] as ['err', Error];
          } else if (typeof e === 'string') {
            return ['err', new Error(e)] as ['err', Error];
          } else {
            return ['err', new Error(JSON.stringify(e))] as ['err', Error];
          }
        }
        return [t, v] as ['ok', T];
      }
    };
    return new KResult<T, Error>(closure());
  }

  ok(): Option<T> {
    const closure = async (): Promise<ISome<T> | INone> => {
      const [t, v] = await this.value;
      if (t === 'ok') {
        return ['some', v] as ['some', T];
      } else {
        return ['none', null] as ['none', null];
      }
    };
    return new KOption<T>(closure());
  }

  run(sideEffect: ((t: T) => void) | ((t: T) => Promise<void>)): Result<T, X> {
    return new KResult<T, X>(
      (async () => {
        const [t, v] = await this.value;
        if (t === 'err') {
          return [t, v];
        } else {
          await sideEffect(v);
          return [t, v];
        }
      })(),
    );
  }

  async serial(): Promise<ResultSerial<T, X>> {
    const r = await this.value;
    return r;
  }
}

export { Err, Ok, Res, KResult };
export type { Result, ResultSerial };
