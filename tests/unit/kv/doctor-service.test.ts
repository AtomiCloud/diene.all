import { describe, it } from 'bun:test';
import should from 'should';
import { DoctorService } from '../../../src/lib/kv/doctor-service';
import { FakeKeyValueStore, FakeShell } from '../../helpers/fakes';

describe('DoctorService', () => {
  describe('platform', () => {
    it('should return the string reported by the shell', async () => {
      // Arrange
      const expected = 'Darwin 25.0.0 arm64';
      const subject = new DoctorService(new FakeKeyValueStore(), new FakeShell(expected));

      // Act
      const actual = await subject.platform();

      // Assert
      should(actual).equal(expected);
    });
  });

  describe('probeBackend', () => {
    it('should return true when the probe key round-trips through the store', async () => {
      // Arrange
      const store = new FakeKeyValueStore();
      const subject = new DoctorService(store, new FakeShell('Linux'));

      // Act
      const actual = await subject.probeBackend();

      // Assert
      should(actual).be.true();
      should(store.setCalls[0]?.key).equal('doctor:probe');
      should(store.getCalls).deepEqual(['doctor:probe']);
    });

    it('should propagate the error when the store fails', async () => {
      // Arrange
      const expected = new Error('connection refused');
      const store = new FakeKeyValueStore({}, expected);
      const subject = new DoctorService(store, new FakeShell('Linux'));

      // Act
      const actual = subject.probeBackend();

      // Assert
      await should(actual).be.rejectedWith(expected);
    });
  });
});
