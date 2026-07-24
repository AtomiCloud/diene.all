/**
 * Resolve after the given number of seconds.
 *
 * `seconds` must be a finite, non-negative number; any other input rejects the
 * returned promise with a {@link RangeError} rather than scheduling a timer.
 */
export function sleep(seconds: number): Promise<void> {
  if (!Number.isFinite(seconds) || seconds < 0) {
    return Promise.reject(new RangeError(`sleep(seconds) requires a finite, non-negative number; received ${seconds}`));
  }

  return new Promise<void>(resolve => {
    setTimeout(resolve, seconds * 1000);
  });
}

/** A function that intentionally does nothing. */
export function noop(): void {
  // Intentionally empty.
}
