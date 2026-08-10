/**
 * Map `items` through `mapper` with a bounded number of concurrent calls.
 *
 * Results preserve input order regardless of completion order. At most
 * `concurrency` mapper invocations are ever in flight, and no work is launched
 * eagerly beyond that bound — a fixed pool of workers pulls the next item only
 * when it becomes free. A rejected `concurrency` (non-integer or `< 1`) rejects
 * the returned promise with a {@link RangeError}, and any mapper rejection
 * propagates unchanged.
 */
export async function mapWithConcurrency<T, R>(
  items: readonly T[],
  concurrency: number,
  mapper: (item: T, index: number) => Promise<R> | R,
): Promise<R[]> {
  if (!Number.isInteger(concurrency) || concurrency < 1) {
    throw new RangeError(`concurrency must be a positive integer; received ${concurrency}`);
  }

  const results = new Array<R>(items.length);
  const workerCount = Math.min(concurrency, items.length);
  let next = 0;

  const worker = async (): Promise<void> => {
    while (next < items.length) {
      const current = next;
      next += 1;
      results[current] = await mapper(items[current] as T, current);
    }
  };

  const workers: Promise<void>[] = [];
  for (let i = 0; i < workerCount; i += 1) {
    workers.push(worker());
  }

  await Promise.all(workers);
  return results;
}
