import type { Result } from '@atomicloud/diene.result';
import 'should';

// `@atomicloud/diene.result` is async-backed: `unwrap`/`unwrapErr`/`isOk`/`isErr`
// all resolve through a promise even though the port methods return a Result
// directly. These helpers await that promise and assert the branch before
// handing back the resolved value/error.

async function expectOk<T>(result: Result<T, unknown>): Promise<T> {
  (await result.isOk()).should.be.true();
  return result.unwrap();
}

async function expectErr<E>(result: Result<unknown, E>): Promise<E> {
  (await result.isErr()).should.be.true();
  return result.unwrapErr();
}

export { expectErr, expectOk };
