import type { Result } from '@atomicloud/diene.e2e/result';

export function requireResult<T>(result: Result<T, Error>): Promise<T> {
  return result.match({
    err: error => Promise.reject(error),
    ok: value => value,
  });
}
