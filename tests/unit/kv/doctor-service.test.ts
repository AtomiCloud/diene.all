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
    it('should round-trip a unique probe without overwriting a user-owned key', async () => {
      // Arrange
      const userKey = 'doctor:probe';
      const store = new FakeKeyValueStore({ [userKey]: 'user-owned' });
      const subject = new DoctorService(store, new FakeShell('Linux'));

      // Act
      const actual = await subject.probeBackend();

      // Assert
      should(actual).be.true();
      const probeKey = store.setCalls[0]?.key ?? '';
      should(probeKey).match(/^doctor:probe-/);
      should(probeKey).not.equal(userKey);
      should(store.setCalls[0]?.ttlSeconds).equal(30);
      should(store.getCalls).deepEqual([probeKey]);
      should(store.deleteCalls).deepEqual([probeKey]);
      should(await store.get(userKey)).equal('user-owned');
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
