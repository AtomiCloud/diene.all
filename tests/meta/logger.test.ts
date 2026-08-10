import { describe, it } from 'bun:test';
import { type LoggingError, type LogRecord, portError } from '@atomicloud/diene.interfaces';
import { InMemoryLoggerSink } from '@atomicloud/diene.interfaces/test-helper';
import 'should';
import { runFailInjectionContract, runSequenceContract, runSnapshotIsolationContract } from './contract/behaviours.js';
import { expectErr, expectOk } from './support/capture.js';

const ioError = (): LoggingError => portError('logging', 'io', 'emit', 'transport down');
const record: LogRecord = { level: 'info', message: 'hello', attributes: { b: 2, a: 1 } };

describe('InMemoryLoggerSink', () => {
  it('should validate, normalize, and retain an emitted record', async () => {
    const subject = new InMemoryLoggerSink();
    await expectOk(subject.emit(record));

    subject.records.should.have.length(1);
    // attributes normalized to a sorted, frozen record
    Object.keys(subject.records[0]?.attributes ?? {}).should.eql(['a', 'b']);
    subject.calls[0]?.method.should.eql('emit');
  });

  it('should reject an invalid record without retaining it', async () => {
    const subject = new InMemoryLoggerSink();
    const error = await expectErr(subject.emit({ level: 'nope' as never, message: 'x' }));
    error.details.should.eql({ field: 'level' });
    subject.records.should.have.length(0);
    subject.calls.should.have.length(0);
  });

  it('should record the emit call but drop the record on an injected failure', async () => {
    // Arrange
    const subject = new InMemoryLoggerSink();
    subject.failNext(ioError());

    // Act
    const error = await expectErr(subject.emit({ level: 'warn', message: 'x' }));

    // Assert - the call is logged for inspection, the record is not retained
    error.code.should.eql('io');
    subject.calls.should.have.length(1);
    subject.calls[0]?.method.should.eql('emit');
    subject.records.should.have.length(0);
  });

  it('should record flush calls and surface flush failures once', async () => {
    const subject = new InMemoryLoggerSink();
    await expectOk(subject.flush());
    subject.failNext(ioError());
    (await expectErr(subject.flush())).code.should.eql('io');
    await expectOk(subject.flush());

    subject.calls.map(call => call.method).should.eql(['flush', 'flush', 'flush']);
  });

  it('should hand back frozen, independent record and call snapshots', async () => {
    const subject = new InMemoryLoggerSink();
    await expectOk(subject.emit(record));

    const records = subject.records;
    Object.isFrozen(records[0]).should.be.true();
    Object.isFrozen(records[0]?.attributes).should.be.true();
    (subject.records[0] === records[0]).should.be.false();
    // each getter read returns a fresh snapshot — two reads are never identical
    const firstCallsRead = subject.calls;
    const secondCallsRead = subject.calls;
    (firstCallsRead[0] === secondCallsRead[0]).should.be.false();
  });

  it('should satisfy the sequence contract across emit and flush', async () => {
    const subject = new InMemoryLoggerSink();
    let toggle = 0;
    await runSequenceContract({
      label: 'InMemoryLoggerSink',
      record: async () => {
        // alternate emit/flush so both recorded-call shapes are exercised
        if (toggle++ % 2 === 0) await subject.emit({ level: 'debug', message: 'm' });
        else await subject.flush();
      },
      sequences: () => subject.calls.map(call => call.sequence),
    });
  });

  it('should satisfy the one-shot fault-injection contract', async () => {
    const subject = new InMemoryLoggerSink();
    await runFailInjectionContract({
      label: 'InMemoryLoggerSink',
      makeError: () => ioError(),
      injectFailure: error => subject.failNext(error),
      callFallible: () => subject.emit({ level: 'info', message: 'm' }),
    });
  });

  it('should satisfy the snapshot isolation contract', async () => {
    const subject = new InMemoryLoggerSink();
    await runSnapshotIsolationContract({
      label: 'InMemoryLoggerSink',
      produce: async () => {
        await subject.emit({ level: 'info', message: 'm' });
      },
      readSnapshot: () => subject.records,
    });
  });
});
