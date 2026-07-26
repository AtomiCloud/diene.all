import type { Option } from '../lib/option.js';
import type { Result } from '../lib/result.js';

type Variant = 'Ok' | 'Err' | 'Some' | 'None';

function formatPayload(payload: unknown): string {
  try {
    const json = JSON.stringify(payload, null, 2);
    return json ?? String(payload);
  } catch {
    return String(payload);
  }
}

/** A framework-independent assertion failure with an explicit variant diff. */
class TestHelperError extends Error {
  readonly expected: Variant;
  readonly actual: Variant;
  readonly payload?: unknown;

  constructor(expected: Variant, actual: Variant, payload?: unknown) {
    const payloadDiff = actual === 'None' ? '' : `\nActual payload:\n${formatPayload(payload)}`;
    super(`Expected variant: ${expected}\nActual variant: ${actual}${payloadDiff}`);
    this.name = 'TestHelperError';
    this.expected = expected;
    this.actual = actual;
    this.payload = payload;
  }
}

/** Assert an Ok result and return its value for continued test composition. */
async function expectOk<T, E>(actual: Result<T, E>): Promise<T> {
  if (await actual.isOk()) {
    return actual.unwrap();
  }
  throw new TestHelperError('Ok', 'Err', await actual.unwrapErr());
}

/** Assert an Err result and return its error for continued test composition. */
async function expectErr<T, E>(actual: Result<T, E>): Promise<E> {
  if (await actual.isErr()) {
    return actual.unwrapErr();
  }
  throw new TestHelperError('Err', 'Ok', await actual.unwrap());
}

/** Assert a Some option and return its value for continued test composition. */
async function expectSome<T>(actual: Option<T>): Promise<T> {
  if (await actual.isSome()) {
    return actual.unwrap();
  }
  throw new TestHelperError('Some', 'None');
}

/** Assert a None option. */
async function expectNone<T>(actual: Option<T>): Promise<void> {
  if (await actual.isNone()) {
    return;
  }
  throw new TestHelperError('None', 'Some', await actual.unwrap());
}

export { expectErr, expectNone, expectOk, expectSome, TestHelperError };
