import { describe, it } from 'bun:test';
import should from 'should';
import { SetController } from '../../src/adapters/kv/api/set-controller';
import { EXIT_ERROR, EXIT_OK } from '../../src/adapters/cli/exit-codes';
import { KvService } from '../../src/lib/kv/service';
import { FakeKeyValueStore, captureIo } from '../helpers/fakes';

describe('SetController', () => {
  describe('handle', () => {
    it('should write the composed key through the store and report success with exit 0', async () => {
      // Arrange
      const store = new FakeKeyValueStore();
      const io = captureIo();
      const subject = new SetController(new KvService(store), io);

      // Act
      const actual = await subject.handle('Bun Base', 'Sample Key', 'hello');

      // Assert
      should(actual).equal(EXIT_OK);
      should(store.setCalls).have.length(1);
      should(store.setCalls[0]).deepEqual({ key: 'bun-base:sample-key', value: 'hello', ttlSeconds: undefined });
      should(io.successes).deepEqual(['set bun-base:sample-key = hello']);
      should(io.errors).be.empty();
    });

    it('should pass the parsed ttl through and note the expiry in the success message', async () => {
      // Arrange
      const store = new FakeKeyValueStore();
      const io = captureIo();
      const subject = new SetController(new KvService(store), io);

      // Act
      const actual = await subject.handle('ns', 'key', 'v', '60');

      // Assert
      should(actual).equal(EXIT_OK);
      should(store.setCalls[0]?.ttlSeconds).equal(60);
      should(io.successes).deepEqual(['set ns:key = v (expires in 60s)']);
    });

    it.each(['abc', '1.5', '0', '-1', '0x10', '1e2', String(365 * 24 * 60 * 60 + 1)])(
      'should reject invalid --ttl "%s" with exit 1 and not touch the store',
      async input => {
        // Arrange
        const store = new FakeKeyValueStore();
        const io = captureIo();
        const subject = new SetController(new KvService(store), io);

        // Act
        const actual = await subject.handle('ns', 'key', 'v', input);

        // Assert
        should(actual).equal(EXIT_ERROR);
        should(store.setCalls).be.empty();
        should(io.errors[0]).containEql('invalid input');
      },
    );

    it('should reject a namespace that slugifies to empty as invalid input', async () => {
      // Arrange
      const store = new FakeKeyValueStore();
      const io = captureIo();
      const subject = new SetController(new KvService(store), io);
      const input = '!!!';

      // Act
      const actual = await subject.handle(input, 'key', 'v');

      // Assert
      should(actual).equal(EXIT_ERROR);
      should(store.setCalls).be.empty();
      should(io.errors[0]).containEql('invalid input');
    });

    it('should report an unreachable backend with exit 1 when the store fails', async () => {
      // Arrange
      const store = new FakeKeyValueStore({}, new Error('connect ECONNREFUSED 127.0.0.1:6379'));
      const io = captureIo();
      const subject = new SetController(new KvService(store), io);

      // Act
      const actual = await subject.handle('ns', 'key', 'v');

      // Assert
      should(actual).equal(EXIT_ERROR);
      should(io.errors[0]).containEql('failed to reach key-value backend');
    });
  });
});
