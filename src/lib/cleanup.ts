/** Run cleanup while preserving an operation error as the authoritative failure. */
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
      try {
        onCleanupFailure(cleanupError);
      } catch {
        // Reporting is best-effort because it must not replace the operation error either.
      }
    }
    throw error;
  }

  await cleanup();
  return result;
}
