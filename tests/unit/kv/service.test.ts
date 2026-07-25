import { describe, it } from 'bun:test';
import should from 'should';
import { KvService } from '../../../src/lib/kv/service';
import { FakeKeyValueStore, captureProgress } from '../../helpers/fakes';

describe('KvService', () => {
  describe('setValue', () => {
    it('should compose the namespaced key via slug and write it through the store', async () => {
      // Arrange
      const store = new FakeKeyValueStore();
      const subject = new KvService(store);
      const expected = 'bun-base:sample-key';

      // Act
      const actual = await subject.setValue('Bun Base', 'Sample Key', 'hello');

      // Assert
      should(actual).equal(expected);
      should(store.setCalls).have.length(1);
      should(store.setCalls[0]).deepEqual({ key: expected, value: 'hello', ttlSeconds: undefined });
    });

    it('should pass the ttl through to the store', async () => {
      // Arrange
      const store = new FakeKeyValueStore();
      const subject = new KvService(store);
      const input = 60;

      // Act
      await subject.setValue('ns', 'key', 'v', input);

      // Assert
      should(store.setCalls[0]?.ttlSeconds).equal(input);
    });
  });

  describe('getValue', () => {
    it('should return the composed key and the stored value', async () => {
      // Arrange
      const store = new FakeKeyValueStore({ 'ns:key': 'hello' });
      const subject = new KvService(store);
      const expected = { composed: 'ns:key', value: 'hello' };

      // Act
      const actual = await subject.getValue('ns', 'key');

      // Assert
      should(actual).deepEqual(expected);
      should(store.getCalls).deepEqual(['ns:key']);
    });

    it('should return a null value for a missing key', async () => {
      // Arrange
      const store = new FakeKeyValueStore();
      const subject = new KvService(store);
      const expected = { composed: 'ns:missing', value: null };

      // Act
      const actual = await subject.getValue('ns', 'missing');

      // Assert
      should(actual).deepEqual(expected);
    });
  });

  describe('seed', () => {
    it('should write N entries, start progress with the total, tick N times, and stop', async () => {
      // Arrange
      const store = new FakeKeyValueStore();
      const progress = captureProgress();
      const subject = new KvService(store);
      const input = 3;

      // Act
      await subject.seed('ns', input, progress);

      // Assert
      should(store.setCalls).have.length(input);
      should(store.setCalls.map(call => call.key)).deepEqual(['ns:sample-1', 'ns:sample-2', 'ns:sample-3']);
      should(store.setCalls.map(call => call.value)).deepEqual(['value-1', 'value-2', 'value-3']);
      should(progress.totals).deepEqual([input]);
      should(progress.ticks).equal(input);
      should(progress.stopped).be.true();
    });

    it('should stop the progress reporter and propagate the error when the store throws mid-way', async () => {
      // Arrange
      const expected = new Error('connect ECONNREFUSED 127.0.0.1:6379');
      const store = new FakeKeyValueStore({}, expected);
      const progress = captureProgress();
      const subject = new KvService(store);

      // Act
      const actual = subject.seed('ns', 3, progress);

      // Assert
      await should(actual).be.rejectedWith(expected);
      should(progress.stopped).be.true();
    });
  });
});
