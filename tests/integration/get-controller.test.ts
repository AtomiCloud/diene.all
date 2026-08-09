import { describe, it } from 'bun:test';
import should from 'should';
import { GetController } from '../../src/adapters/kv/api/get-controller';
import { EXIT_ERROR, EXIT_OK } from '../../src/adapters/cli/exit-codes';
import { KvService } from '../../src/lib/kv/service';
import { FakeKeyValueStore, FakePrompt, captureIo } from '../helpers/fakes';

describe('GetController', () => {
  describe('handle', () => {
    it('should print the stored value and return exit 0 when the key is found', async () => {
      // Arrange
      const expected = 'hello';
      const store = new FakeKeyValueStore({ 'ns:key': expected });
      const io = captureIo();
      const subject = new GetController(new KvService(store), io, new FakePrompt('unused'), false);

      // Act
      const actual = await subject.handle('ns', 'key');

      // Assert
      should(actual).equal(EXIT_OK);
      should(io.successes[0]).equal(expected);
      should(io.errors).be.empty();
    });

    it('should warn and return exit 1 when the key is missing', async () => {
      // Arrange
      const store = new FakeKeyValueStore();
      const io = captureIo();
      const subject = new GetController(new KvService(store), io, new FakePrompt('unused'), false);

      // Act
      const actual = await subject.handle('ns', 'key');

      // Assert
      should(actual).equal(EXIT_ERROR);
      should(io.warnings[0]).containEql('not found: ns:key');
    });

    it('should fail fast with a missing-argument error when the key is omitted non-interactively', async () => {
      // Arrange
      const store = new FakeKeyValueStore({ 'ns:key': 'hello' });
      const io = captureIo();
      const subject = new GetController(new KvService(store), io, new FakePrompt('key'), false);

      // Act
      const actual = await subject.handle('ns');

      // Assert
      should(actual).equal(EXIT_ERROR);
      should(io.errors[0]).containEql('missing argument: key');
      should(store.getCalls).be.empty();
    });

    it('should prompt for the key and return its value when omitted interactively', async () => {
      // Arrange
      const expected = 'hello';
      const store = new FakeKeyValueStore({ 'ns:prompted-key': expected });
      const io = captureIo();
      const subject = new GetController(new KvService(store), io, new FakePrompt('Prompted Key'), true);

      // Act
      const actual = await subject.handle('ns');

      // Assert
      should(actual).equal(EXIT_OK);
      should(store.getCalls).deepEqual(['ns:prompted-key']);
      should(io.successes[0]).equal(expected);
    });

    it('should report an unreachable backend with exit 1 when the store fails', async () => {
      // Arrange
      const store = new FakeKeyValueStore({}, new Error('connect ECONNREFUSED 127.0.0.1:6379'));
      const io = captureIo();
      const subject = new GetController(new KvService(store), io, new FakePrompt('unused'), false);

      // Act
      const actual = await subject.handle('ns', 'key');

      // Assert
      should(actual).equal(EXIT_ERROR);
      should(io.errors[0]).containEql('failed to reach key-value backend');
    });
  });
});
