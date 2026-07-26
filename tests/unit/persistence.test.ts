import { describe, it } from 'bun:test';
import should from 'should';
import {
  CLEAR_TRIGGERS,
  type ClearTrigger,
  createDraftStore,
  type DismissReason,
  type DraftStoragePort,
} from '../../src/lib/persistence/index';

const fakeStorage = (initial: Record<string, string> = {}) => {
  const map = new Map<string, string>(Object.entries(initial));
  const port: DraftStoragePort = {
    get: key => map.get(key) ?? null,
    set: (key, value) => {
      map.set(key, value);
    },
    remove: key => {
      map.delete(key);
    },
  };
  return { port, map };
};

interface Draft {
  readonly title: string;
}

describe('persistence · draft store', () => {
  it('should save and load a round-tripped draft', () => {
    // Arrange
    const storage = fakeStorage();
    const store = createDraftStore<Draft>({ key: 'form:new', storage: storage.port });

    // Act
    store.save({ title: 'hello' });

    // Assert
    should(store.load()).deepEqual({ title: 'hello' });
    should(store.has()).be.true();
    should(storage.map.get('form:new')).equal('{"title":"hello"}');
  });

  it('should return undefined when no draft is persisted', () => {
    const store = createDraftStore<Draft>({ key: 'absent', storage: fakeStorage().port });
    should(store.load()).be.undefined();
    should(store.has()).be.false();
  });

  it('should tolerate malformed JSON by returning undefined', () => {
    // Arrange
    const storage = fakeStorage({ 'form:x': '{not json' });
    const store = createDraftStore<Draft>({ key: 'form:x', storage: storage.port });

    // Act & Assert
    should(store.load()).be.undefined();
    should(store.has()).be.false();
  });

  it('should clear the draft on each terminal trigger and report the trigger', () => {
    // Arrange
    const cleared: ClearTrigger[] = [];
    for (const trigger of CLEAR_TRIGGERS) {
      const storage = fakeStorage();
      const store = createDraftStore<Draft>({
        key: 'form:new',
        storage: storage.port,
        onCleared: t => cleared.push(t),
      });
      store.save({ title: 'draft' });

      // Act
      store.clear(trigger);

      // Assert
      should(store.has()).be.false();
      should(storage.map.has('form:new')).be.false();
    }
    should(cleared).deepEqual(['cancel', 'close', 'submit', 'reset']);
  });

  it('should keep the draft and offer a restore on accidental dismissal', () => {
    // Arrange
    const offers: Array<{ reason: DismissReason; draft: Draft }> = [];
    const storage = fakeStorage();
    const store = createDraftStore<Draft>({
      key: 'form:new',
      storage: storage.port,
      onRestoreOffer: (reason, draft) => offers.push({ reason, draft }),
    });
    store.save({ title: 'unsent' });

    // Act
    const restored = store.dismiss('backdrop');

    // Assert
    should(restored).deepEqual({ title: 'unsent' });
    should(store.has()).be.true();
    should(offers).deepEqual([{ reason: 'backdrop', draft: { title: 'unsent' } }]);
  });

  it('should not offer a restore when there is no draft to dismiss', () => {
    // Arrange
    let offered = false;
    const store = createDraftStore<Draft>({
      key: 'form:new',
      storage: fakeStorage().port,
      onRestoreOffer: () => {
        offered = true;
      },
    });

    // Act
    const restored = store.dismiss('back');

    // Assert
    should(restored).be.undefined();
    should(offered).be.false();
  });
});
