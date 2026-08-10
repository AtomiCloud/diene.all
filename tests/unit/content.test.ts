import { describe, it } from 'bun:test';
import type { Problem } from '@atomicloud/diene.problems';
import should from 'should';
import {
  type ContentState,
  createContentStore,
  createProblemViewRegistry,
  DEFAULT_EMPTY_REASON,
  errorContentState,
  isEmptyContent,
  isLocalError,
  LOCAL_ERROR_TYPE,
  localErrorProblem,
  resolveContentState,
  toProblem,
} from '../../src/lib/content/index';

const deferred = <T>() => {
  let resolve!: (value: T) => void;
  let reject!: (reason: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
};

const goodProblem: Problem = { type: 'urn:test:x', title: 'X', status: 400, data: {} };

describe('content · LocalError wrapping', () => {
  it('should wrap an Error preserving message, name and stack', () => {
    // Arrange
    const error = new Error('boom');

    // Act
    const problem = localErrorProblem(error);

    // Assert
    should(problem.type).equal(LOCAL_ERROR_TYPE);
    should(problem.data.message).equal('boom');
    should(problem.data.name).equal('Error');
    should(problem.data.stack).be.a.String();
    should(isLocalError(problem)).be.true();
  });

  it('should wrap a string throw', () => {
    // Act
    const problem = localErrorProblem('plain');

    // Assert
    should(problem.data.message).equal('plain');
    should(problem.detail).equal('plain');
  });

  it('should wrap a serialisable object throw', () => {
    // Act
    const problem = localErrorProblem({ code: 7 });

    // Assert
    should(problem.data.message).equal('{"code":7}');
  });

  it('should fall back to String() when the value is not JSON-serialisable', () => {
    // Act
    const problem = localErrorProblem(undefined);

    // Assert
    should(problem.data.message).equal('undefined');
  });

  it('should fall back to String() when JSON.stringify throws', () => {
    // Arrange
    const circular: Record<string, unknown> = {};
    circular.self = circular;

    // Act
    const problem = localErrorProblem(circular);

    // Assert
    should(problem.data.message).equal('[object Object]');
  });

  it('should report non-LocalError problems via isLocalError', () => {
    should(isLocalError(goodProblem)).be.false();
  });
});

describe('content · toProblem', () => {
  it('should pass an existing Problem through unchanged', () => {
    should(toProblem(goodProblem)).equal(goodProblem);
  });

  it('should wrap a non-Problem throw', () => {
    should(toProblem(new Error('nope')).type).equal(LOCAL_ERROR_TYPE);
  });
});

describe('content · emptiness', () => {
  it('should treat empty arrays and nullish as empty and everything else as content', () => {
    should(isEmptyContent([])).be.true();
    should(isEmptyContent([1])).be.false();
    should(isEmptyContent(null)).be.true();
    should(isEmptyContent(undefined)).be.true();
    should(isEmptyContent(0)).be.false();
    should(isEmptyContent({ a: 1 })).be.false();
  });
});

describe('content · pure state transitions', () => {
  it('should resolve non-empty data to the content state', () => {
    should(resolveContentState('hello')).deepEqual({ status: 'content', data: 'hello' });
  });

  it('should resolve empty data to the empty state with the default reason', () => {
    should(resolveContentState([])).deepEqual({ status: 'empty', reason: DEFAULT_EMPTY_REASON });
  });

  it('should honour a custom emptyChecker and notFound reason', () => {
    // Act
    const state = resolveContentState('x', { emptyChecker: () => true, notFound: 'Nothing here' });

    // Assert
    should(state).deepEqual({ status: 'empty', reason: 'Nothing here' });
  });

  it('should build an error state carrying a Problem', () => {
    // Act
    const state = errorContentState(new Error('bad'));

    // Assert
    should(state.status).equal('error');
    if (state.status === 'error') should(state.problem.type).equal(LOCAL_ERROR_TYPE);
  });
});

describe('content · store', () => {
  it('should start idle by default and honour an initial state', () => {
    should(createContentStore().getState()).deepEqual({ status: 'idle' });
    should(createContentStore<number>({ initial: { status: 'content', data: 1 } }).getState()).deepEqual({
      status: 'content',
      data: 1,
    });
  });

  it('should notify subscribers of loading then content, and stop after unsubscribe', async () => {
    // Arrange
    const store = createContentStore<string>();
    const seen: ContentState<string>[] = [];
    const unsubscribe = store.subscribe(state => seen.push(state));

    // Act
    await store.load(() => 'value');
    unsubscribe();
    await store.load(() => 'again');

    // Assert
    should(seen.map(s => s.status)).deepEqual(['loading', 'content']);
    should(store.getState()).deepEqual({ status: 'content', data: 'again' });
  });

  it('should transition to empty for empty resolutions', async () => {
    // Arrange
    const store = createContentStore<number[]>({ notFound: 'None' });

    // Act
    await store.load(() => []);

    // Assert
    should(store.getState()).deepEqual({ status: 'empty', reason: 'None' });
  });

  it('should transition to error when the source throws', async () => {
    // Arrange
    const store = createContentStore<string>();

    // Act
    await store.load(() => {
      throw new Error('kaboom');
    });

    // Assert
    const state = store.getState();
    should(state.status).equal('error');
  });

  it('should reset back to idle', async () => {
    // Arrange
    const store = createContentStore<string>();
    await store.load(() => 'x');

    // Act
    store.reset();

    // Assert
    should(store.getState()).deepEqual({ status: 'idle' });
  });

  it('should discard a stale successful resolution (latest wins)', async () => {
    // Arrange
    const store = createContentStore<string>();
    const first = deferred<string>();
    const second = deferred<string>();

    // Act
    const p1 = store.load(() => first.promise);
    const p2 = store.load(() => second.promise);
    second.resolve('newer');
    await p2;
    first.resolve('older');
    await p1;

    // Assert
    should(store.getState()).deepEqual({ status: 'content', data: 'newer' });
  });

  it('should discard a stale failed resolution (latest wins)', async () => {
    // Arrange
    const store = createContentStore<string>();
    const first = deferred<string>();
    const second = deferred<string>();

    // Act
    const p1 = store.load(() => first.promise);
    const p2 = store.load(() => second.promise);
    second.resolve('newer');
    await p2;
    first.reject(new Error('stale failure'));
    await p1;

    // Assert
    should(store.getState()).deepEqual({ status: 'content', data: 'newer' });
  });
});

describe('content · problem view registry', () => {
  it('should render the fallback view for unknown problem types', () => {
    // Arrange
    const registry = createProblemViewRegistry<string>(problem => `fallback:${problem.type}`);

    // Act & Assert
    should(registry.has('urn:test:x')).be.false();
    should(registry.resolve(goodProblem)).equal('fallback:urn:test:x');
  });

  it('should render a registered per-type override', () => {
    // Arrange
    const registry = createProblemViewRegistry<string>(() => 'fallback');
    registry.register('urn:test:x', problem => `custom:${problem.title}`);

    // Act & Assert
    should(registry.has('urn:test:x')).be.true();
    should(registry.resolve(goodProblem)).equal('custom:X');
  });
});
