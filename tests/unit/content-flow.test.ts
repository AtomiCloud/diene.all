import { describe, it } from 'bun:test';
import should from 'should';
import { createContentStore, isLocalError } from '@atomicloud/diene.frontend-utils/content';
import { isEmptyFlowResult, runContentFlow } from '../../src/lib/content-flow';

// The template's content flow owns the emptiness POLICY over the lib's L/E/E
// store: a resolved payload becomes content, empty, or error — never a payload
// that renders as content while being empty.

describe('isEmptyFlowResult', () => {
  it.each([
    { label: 'an empty array', value: [] as unknown, expected: true },
    { label: 'null', value: null as unknown, expected: true },
    { label: 'undefined', value: undefined as unknown, expected: true },
    { label: 'a populated array', value: [1] as unknown, expected: false },
    { label: 'an object', value: { landscape: 'base' } as unknown, expected: false },
  ])('should report $label as empty=$expected', ({ value, expected }) => {
    // Arrange

    // Act
    const actual = isEmptyFlowResult(value);

    // Assert
    should(actual).equal(expected);
  });
});

describe('runContentFlow', () => {
  it('should resolve a populated payload to the content state', async () => {
    // Arrange
    const store = createContentStore<{ service: string }>();

    // Act
    const actual = await runContentFlow(store, () => ({ service: 'nextjs-frontend' }));

    // Assert
    should(actual.status).equal('content');
    if (actual.status === 'content') should(actual.data.service).equal('nextjs-frontend');
  });

  it('should resolve an empty payload to the empty state with the configured reason', async () => {
    // Arrange
    const store = createContentStore<readonly string[]>();

    // Act
    const actual = await runContentFlow(store, () => [], 'nothing here');

    // Assert
    should(actual.status).equal('empty');
    if (actual.status === 'empty') should(actual.reason).equal('nothing here');
  });

  it('should fall back to the default empty reason when none is supplied', async () => {
    // Arrange
    const store = createContentStore<readonly string[]>();

    // Act
    const actual = await runContentFlow(store, () => []);

    // Assert
    should(actual.status).equal('empty');
    if (actual.status === 'empty') should(actual.reason.length).be.above(0);
  });

  it('should override a store that admitted an empty payload as content', async () => {
    // Arrange — the store is built with emptiness detection disabled, so only
    // the flow's own policy can stop an empty payload reaching the content branch.
    const store = createContentStore<readonly string[]>({ emptyChecker: () => false });

    // Act
    const actual = await runContentFlow(store, () => [], 'flow caught it');

    // Assert
    should(actual.status).equal('empty');
    if (actual.status === 'empty') should(actual.reason).equal('flow caught it');
  });

  it('should wrap a thrown source into the error state carrying a LocalError Problem', async () => {
    // Arrange
    const store = createContentStore<{ service: string }>();

    // Act
    const actual = await runContentFlow(store, () => {
      throw new Error('source exploded');
    });

    // Assert
    should(actual.status).equal('error');
    if (actual.status === 'error') should(isLocalError(actual.problem)).equal(true);
  });
});
