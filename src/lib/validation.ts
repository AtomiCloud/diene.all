import { Err, Ok, type Result } from '@atomicloud/diene.result';

type Checked<T, E> = { readonly ok: true; readonly value: T } | { readonly error: E; readonly ok: false };

function accepted<T>(value: T): Checked<T, never> {
  return Object.freeze({ ok: true, value });
}

function rejected<E>(error: E): Checked<never, E> {
  return Object.freeze({ error, ok: false });
}

function resultFromChecked<T, E>(checked: Checked<T, E>): Result<T, E> {
  return checked.ok ? Ok<T, E>(checked.value) : Err<T, E>(checked.error);
}

export type { Checked };
export { accepted, rejected, resultFromChecked };
