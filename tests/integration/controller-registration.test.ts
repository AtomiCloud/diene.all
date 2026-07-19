import { describe, expect, it } from 'bun:test';
import { Command } from 'commander';
import { DoctorController } from '../../src/adapters/kv/api/doctor-controller';
import { GetController } from '../../src/adapters/kv/api/get-controller';
import { SeedController } from '../../src/adapters/kv/api/seed-controller';
import { SetController } from '../../src/adapters/kv/api/set-controller';
import { DoctorService } from '../../src/lib/kv/doctor-service';
import { KvService } from '../../src/lib/kv/service';
import { FakeKeyValueStore, FakePrompt, FakeShell, captureIo, captureProgress, captureSpinner } from '../helpers/fakes';

function program(): Command {
  return new Command().name('bun-cli').exitOverride();
}

describe('controller registration', () => {
  it('should bind each controller action to its handler', async () => {
    const store = new FakeKeyValueStore({ 'demo:key': 'found' });
    const kv = new KvService(store);

    const setIo = captureIo();
    const setProgram = program();
    new SetController(kv, setIo).register(setProgram);
    await setProgram.parseAsync(['bun', 'bun-cli', 'set', 'demo', 'key', 'value']);
    expect(setIo.exitCodes).toEqual([0]);

    const getIo = captureIo();
    const getProgram = program();
    new GetController(kv, getIo, new FakePrompt('key'), false).register(getProgram);
    await getProgram.parseAsync(['bun', 'bun-cli', 'get', 'demo', 'key']);
    expect(getIo.exitCodes).toEqual([0]);

    const seedIo = captureIo();
    const seedProgram = program();
    new SeedController(kv, seedIo, captureProgress()).register(seedProgram);
    await seedProgram.parseAsync(['bun', 'bun-cli', 'seed', 'demo', '1']);
    expect(seedIo.exitCodes).toEqual([0]);

    const doctorIo = captureIo();
    const doctorProgram = program();
    new DoctorController(new DoctorService(store, new FakeShell('linux')), doctorIo, captureSpinner()).register(
      doctorProgram,
    );
    await doctorProgram.parseAsync(['bun', 'bun-cli', 'doctor']);
    expect(doctorIo.exitCodes).toEqual([0]);
  });
});
