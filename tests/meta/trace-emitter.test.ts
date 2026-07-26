import { describe, it } from 'bun:test';
import { traceError, type TraceRecord } from '@atomicloud/diene.otel';
import { InMemoryTraceEmitter } from '@atomicloud/diene.otel/test-helper';
import 'should';
import { expectErr, expectOk } from './support/capture';

// The InMemoryTraceEmitter is the RB-19 language-local trace mock owned by this
// lib. It must record immutable clones, honour failNext, and skip recording the
// span payload when a failure is injected.

const fullRecord: TraceRecord = {
  name: 'http.request',
  attributes: { 'http.method': 'GET' },
  events: [{ name: 'sent', attributes: { bytes: 4 } }, { name: 'received' }],
  status: 'ok',
  statusMessage: 'done',
};

describe('InMemoryTraceEmitter', () => {
  it('should record frozen clones of emitted records and a mixed call log', async () => {
    // Arrange
    const subject = new InMemoryTraceEmitter();

    // Act - a full record, a minimal record, then a flush
    await expectOk(subject.emit(fullRecord));
    await expectOk(subject.emit({ name: 'minimal' }));
    await expectOk(subject.flush());

    // Assert - records are frozen clones carrying every optional field faithfully
    const records = subject.records;
    records.length.should.eql(2);
    Object.isFrozen(records[0]).should.be.true();
    records[0]?.should.eql(fullRecord);
    records[1]?.should.eql({ name: 'minimal' });

    // Assert - the call log interleaves emit and flush entries with sequences
    const calls = subject.calls;
    calls.length.should.eql(3);
    calls[0]?.should.containEql({ method: 'emit', sequence: 0 });
    calls[2]?.should.eql({ method: 'flush', sequence: 2 });
  });

  it('should return an independent snapshot from the records getter', async () => {
    // Arrange
    const subject = new InMemoryTraceEmitter();
    await expectOk(subject.emit({ name: 'once' }));

    // Act - two reads must not share a reference
    const first = subject.records;
    const second = subject.records;

    // Assert
    (first === second).should.be.false();
    first.should.eql(second);
  });

  it('should reject a malformed record without recording it', async () => {
    // Arrange
    const subject = new InMemoryTraceEmitter();

    // Act
    const error = await expectErr(subject.emit({ name: '' } as TraceRecord));

    // Assert
    error.code.should.eql('invalid-input');
    subject.records.length.should.eql(0);
    subject.calls.length.should.eql(0);
  });

  it('should honour failNext on emit, recording the call but not the record', async () => {
    // Arrange
    const subject = new InMemoryTraceEmitter();
    subject.failNext(traceError('unavailable', 'emit', 'injected'));

    // Act
    const error = await expectErr(subject.emit({ name: 'work' }));

    // Assert - the attempt is logged, but the payload is withheld
    error.code.should.eql('unavailable');
    subject.calls.length.should.eql(1);
    subject.records.length.should.eql(0);

    // Act - the next emit succeeds (the failure is one-shot)
    await expectOk(subject.emit({ name: 'work' }));

    // Assert
    subject.records.length.should.eql(1);
  });

  it('should honour failNext on flush', async () => {
    // Arrange
    const subject = new InMemoryTraceEmitter();
    subject.failNext(traceError('io', 'flush', 'injected'));

    // Act
    const error = await expectErr(subject.flush());

    // Assert
    error.operation.should.eql('flush');
  });
});
