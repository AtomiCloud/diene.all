/**
 * Run `operation`, then `cleanup`, without ever letting a cleanup failure hide a real one.
 *
 * `try { ... } finally { await cleanup(); }` looks equivalent but is not: a throwing `finally`
 * replaces the in-flight error, so a Redis disconnect that fails on the way out erases the fault
 * that actually broke the run. Here the operation's error always wins and the cleanup failure is
 * reported separately through `onCleanupFailure`.
 *
 * When the operation succeeds, a cleanup failure is the only failure there is, so it propagates.
 */
export async function withCleanup<T>(
  operation: () => Promise<T>,
  cleanup: () => Promise<void>,
  onCleanupFailure: (error: unknown) => void,
): Promise<T> {
  let result: T;

  try {
    result = await operation();
  } catch (error) {
    try {
      await cleanup();
    } catch (cleanupError) {
      onCleanupFailure(cleanupError);
    }
    throw error;
  }

  await cleanup();
  return result;
}
