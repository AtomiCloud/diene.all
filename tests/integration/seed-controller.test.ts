import { describe, it } from 'bun:test';
import should from 'should';
import { SeedController } from '../../src/adapters/kv/api/seed-controller';
import { EXIT_ERROR, EXIT_OK } from '../../src/adapters/cli/exit-codes';
import { KvService } from '../../src/lib/kv/service';
import { FakeKeyValueStore, captureIo, captureProgress } from '../helpers/fakes';

describe('SeedController', () => {
  describe('handle', () => {
    it('should seed the requested entries with progress feedback and return exit 0', async () => {
      // Arrange
      const store = new FakeKeyValueStore();
      const io = captureIo();
      const progress = captureProgress();
      const subject = new SeedController(new KvService(store), io, progress);

      // Act
      const actual = await subject.handle('ns', '3');

      // Assert
      should(actual).equal(EXIT_OK);
      should(store.setCalls).have.length(3);
      should(progress.totals).deepEqual([3]);
      should(progress.ticks).equal(3);
      should(progress.stopped).be.true();
      should(io.successes).deepEqual(['seeded 3 entries under "ns"']);
    });

    it.each(['abc', '0', '-1', '1.5', '10001'])(
      'should reject invalid count "%s" with exit 1 and not touch the store',
      async input => {
        // Arrange
        const store = new FakeKeyValueStore();
        const io = captureIo();
        const progress = captureProgress();
        const subject = new SeedController(new KvService(store), io, progress);

        // Act
        const actual = await subject.handle('ns', input);

        // Assert
        should(actual).equal(EXIT_ERROR);
        should(store.setCalls).be.empty();
        should(io.errors[0]).containEql('invalid input');
      },
    );

    it('should stop the progress reporter and report an unreachable backend when the store fails', async () => {
      // Arrange
      const store = new FakeKeyValueStore({}, new Error('connect ECONNREFUSED 127.0.0.1:6379'));
      const io = captureIo();
      const progress = captureProgress();
      const subject = new SeedController(new KvService(store), io, progress);

      // Act
      const actual = await subject.handle('ns', '3');

      // Assert
      should(actual).equal(EXIT_ERROR);
      should(progress.stopped).be.true();
      should(io.errors[0]).containEql('failed to reach the key-value backend');
    });
  });
});
