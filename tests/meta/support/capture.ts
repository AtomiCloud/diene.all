import type { Result } from '@atomicloud/diene.result';
import 'should';

// Framework-free capture helpers for the meta tier. Shipped assertions throw
// on a bad interaction and return nothing on a good one, so assert-the-asserter
// tests observe both the throw and the no-throw. Result-returning seams resolve
// their branch through a promise, hence the awaited unwrap helpers.

function capture(fn: () => void): unknown {
  try {
    fn();
  } catch (error) {
    return error;
  }
  return undefined;
}

function expectThrow(fn: () => void): unknown {
  const error = capture(fn);
  (error === undefined).should.be.false();
  return error;
}

function expectNoThrow(fn: () => void): void {
  (capture(fn) === undefined).should.be.true();
}

async function expectOk<T>(result: Result<T, unknown>): Promise<T> {
  (await result.isOk()).should.be.true();
  return result.unwrap();
}

async function expectErr<E>(result: Result<unknown, E>): Promise<E> {
  (await result.isErr()).should.be.true();
  return result.unwrapErr();
}

export { expectErr, expectNoThrow, expectOk, expectThrow };
