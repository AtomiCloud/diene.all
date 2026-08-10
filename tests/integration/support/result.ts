import type { Result } from '@atomicloud/diene.result';
import 'should';

// `@atomicloud/diene.result` resolves its branch predicates through a promise,
// so these helpers await the branch before handing back the value or error.

async function expectOk<T>(result: Result<T, unknown>): Promise<T> {
  (await result.isOk()).should.be.true();
  return result.unwrap();
}

async function expectErr<E>(result: Result<unknown, E>): Promise<E> {
  (await result.isErr()).should.be.true();
  return result.unwrapErr();
}

export { expectErr, expectOk };
