import { describe, it } from 'bun:test';
import should from 'should';
import { DoctorController } from '../../src/adapters/kv/api/doctor-controller';
import { EXIT_ERROR, EXIT_OK } from '../../src/adapters/cli/exit-codes';
import { DoctorService } from '../../src/lib/kv/doctor-service';
import { FakeKeyValueStore, FakeShell, captureIo, captureSpinner } from '../helpers/fakes';

describe('DoctorController', () => {
  describe('handle', () => {
    it('should report the platform and a reachable backend with exit 0', async () => {
      // Arrange
      const store = new FakeKeyValueStore();
      const io = captureIo();
      const spinner = captureSpinner();
      const subject = new DoctorController(new DoctorService(store, new FakeShell('Darwin 25.0.0 arm64')), io, spinner);

      // Act
      const actual = await subject.handle();

      // Assert
      should(actual).equal(EXIT_OK);
      should(io.successes[0]).equal('platform: Darwin 25.0.0 arm64');
      should(spinner.events.at(-1)).equal('succeed:key-value backend reachable');
    });

    it('should fail the spinner and return exit 1 when the backend is unreachable', async () => {
      // Arrange
      const store = new FakeKeyValueStore({}, new Error('connection refused'));
      const io = captureIo();
      const spinner = captureSpinner();
      const subject = new DoctorController(new DoctorService(store, new FakeShell('Linux')), io, spinner);

      // Act
      const actual = await subject.handle();

      // Assert
      should(actual).equal(EXIT_ERROR);
      should(spinner.events.at(-1)).containEql('fail:key-value backend unreachable');
    });

    it('should degrade to a warning and still return exit 0 when the shell fails', async () => {
      // Arrange
      const store = new FakeKeyValueStore();
      const io = captureIo();
      const spinner = captureSpinner();
      const subject = new DoctorController(
        new DoctorService(store, new FakeShell(new Error('uname not found'))),
        io,
        spinner,
      );

      // Act
      const actual = await subject.handle();

      // Assert
      should(actual).equal(EXIT_OK);
      should(io.warnings[0]).containEql('could not detect platform');
      should(io.successes).be.empty();
    });
  });
});
