import { describe, it } from 'bun:test';
import should from 'should';
import { createDraftStore, type DraftStoragePort } from '@atomicloud/diene.frontend-utils/persistence';
import { DRAFT_KEY_PREFIX, buildDraftKey, shouldOfferRestore } from '../../src/lib/form-draft';

// The draft CONTRACT: the lib store persists/clears through an injected port,
// and the template's policy decides the key namespace plus whether a loaded
// draft is worth offering back.

const fakeStorage = (): DraftStoragePort & { readonly entries: Map<string, string> } => {
  const entries = new Map<string, string>();
  return {
    entries,
    get: key => entries.get(key) ?? null,
    set: (key, value) => {
      entries.set(key, value);
    },
    remove: key => {
      entries.delete(key);
    },
  };
};

describe('buildDraftKey', () => {
  it('should namespace the form name under the app draft prefix', () => {
    // Arrange
    const form = 'settings-form';
    const expected = `${DRAFT_KEY_PREFIX}.settings-form`;

    // Act
    const actual = buildDraftKey(form);

    // Assert
    should(actual).equal(expected);
  });

  it('should trim surrounding whitespace from the form name', () => {
    // Arrange
    const form = '  settings-form  ';

    // Act
    const actual = buildDraftKey(form);

    // Assert
    should(actual).equal(`${DRAFT_KEY_PREFIX}.settings-form`);
  });

  it('should reject a blank form name', () => {
    // Arrange
    const form = '   ';

    // Act
    const actual = () => buildDraftKey(form);

    // Assert
    should(actual).throw('draft form name must not be blank');
  });
});

describe('shouldOfferRestore', () => {
  it.each([
    { label: 'an absent draft', draft: undefined, expected: false },
    { label: 'a draft with no fields', draft: {}, expected: false },
    { label: 'a draft with only blank strings', draft: { name: '', email: '   ' }, expected: false },
    { label: 'a draft with real input', draft: { name: 'Draft User', email: '' }, expected: true },
    { label: 'a draft with a non-string value', draft: { budget: 42 }, expected: true },
    { label: 'a draft with only nullish values', draft: { budget: null }, expected: false },
  ])('should return $expected for $label', ({ draft, expected }) => {
    // Arrange

    // Act
    const actual = shouldOfferRestore(draft as Record<string, unknown> | undefined);

    // Assert
    should(actual).equal(expected);
  });
});

describe('the draft store bound to the app key policy', () => {
  it('should round-trip a draft through the namespaced key', () => {
    // Arrange
    const storage = fakeStorage();
    const store = createDraftStore<{ displayName: string }>({ key: buildDraftKey('settings-form'), storage });

    // Act
    store.save({ displayName: 'Draft User' });

    // Assert
    should(storage.entries.has(`${DRAFT_KEY_PREFIX}.settings-form`)).equal(true);
    should(store.load()?.displayName).equal('Draft User');
    should(shouldOfferRestore(store.load())).equal(true);
  });

  it('should clear the draft on a terminal trigger', () => {
    // Arrange
    const storage = fakeStorage();
    const store = createDraftStore<{ displayName: string }>({ key: buildDraftKey('settings-form'), storage });
    store.save({ displayName: 'Draft User' });

    // Act
    store.clear('submit');

    // Assert
    should(store.load()).be.undefined();
    should(shouldOfferRestore(store.load())).equal(false);
  });

  it('should preserve the draft on an accidental dismissal and offer it back', () => {
    // Arrange
    const storage = fakeStorage();
    const store = createDraftStore<{ displayName: string }>({ key: buildDraftKey('settings-form'), storage });
    store.save({ displayName: 'Draft User' });

    // Act
    const offered = store.dismiss('backdrop');

    // Assert
    should(offered?.displayName).equal('Draft User');
    should(shouldOfferRestore(offered)).equal(true);
  });
});
