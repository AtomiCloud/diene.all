import { InterfaceAssertionError } from '@atomicloud/diene.interfaces/test-helper';
import type { Result } from '@atomicloud/diene.result';
import 'should';

// Framework-free capture helpers for the meta tier. The shipped assertions throw
// `InterfaceAssertionError` on a bad interaction and return nothing on a good one,
// so "assert-the-asserter" tests need to observe both the throw and the no-throw.

function capture(fn: () => void): unknown {
  try {
    fn();
  } catch (error) {
    return error;
  }
  return undefined;
}

function expectAssertionError(fn: () => void): InterfaceAssertionError {
  const error = capture(fn);
  (error instanceof InterfaceAssertionError).should.be.true();
  return error as InterfaceAssertionError;
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

export { expectAssertionError, expectErr, expectNoThrow, expectOk };
