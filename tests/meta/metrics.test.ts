import { describe, it } from 'bun:test';
import { type MetricRecord, type MetricsError, portError } from '@atomicloud/diene.interfaces';
import { InMemoryMetricsCollector } from '@atomicloud/diene.interfaces/test-helper';
import 'should';
import { runFailInjectionContract, runSequenceContract, runSnapshotIsolationContract } from './contract/behaviours.js';
import { expectErr, expectOk } from './support/capture.js';

const ioError = (): MetricsError => portError('metrics', 'io', 'record', 'sink down');
const metric: MetricRecord = { kind: 'counter', name: 'hits', value: 3, attributes: { b: 2, a: 1 } };

describe('InMemoryMetricsCollector', () => {
  it('should validate, normalize, and retain a recorded metric', async () => {
    const subject = new InMemoryMetricsCollector();
    await expectOk(subject.record(metric));

    subject.metrics.should.have.length(1);
    Object.keys(subject.metrics[0]?.attributes ?? {}).should.eql(['a', 'b']);
    subject.calls[0]?.method.should.eql('record');
  });

  it('should reject an invalid metric without retaining it', async () => {
    const subject = new InMemoryMetricsCollector();
    const error = await expectErr(subject.record({ kind: 'counter', name: 'x', value: -1 }));
    error.details.should.eql({ field: 'value' });
    subject.metrics.should.have.length(0);
    subject.calls.should.have.length(0);
  });

  it('should record the call but drop the metric on an injected failure', async () => {
    const subject = new InMemoryMetricsCollector();
    subject.failNext(ioError());

    const error = await expectErr(subject.record({ kind: 'gauge', name: 'x', value: 1 }));

    error.code.should.eql('io');
    subject.calls.should.have.length(1);
    subject.calls[0]?.method.should.eql('record');
    subject.metrics.should.have.length(0);
  });

  it('should record flush calls and surface flush failures once', async () => {
    const subject = new InMemoryMetricsCollector();
    await expectOk(subject.flush());
    subject.failNext(ioError());
    (await expectErr(subject.flush())).code.should.eql('io');
    await expectOk(subject.flush());

    subject.calls.map(call => call.method).should.eql(['flush', 'flush', 'flush']);
  });

  it('should hand back frozen, independent metric snapshots', async () => {
    const subject = new InMemoryMetricsCollector();
    await expectOk(subject.record(metric));

    const metrics = subject.metrics;
    Object.isFrozen(metrics[0]).should.be.true();
    Object.isFrozen(metrics[0]?.attributes).should.be.true();
    (subject.metrics[0] === metrics[0]).should.be.false();
  });

  it('should satisfy the sequence contract across record and flush', async () => {
    const subject = new InMemoryMetricsCollector();
    let toggle = 0;
    await runSequenceContract({
      label: 'InMemoryMetricsCollector',
      record: async () => {
        if (toggle++ % 2 === 0) await subject.record({ kind: 'gauge', name: 'g', value: 1 });
        else await subject.flush();
      },
      sequences: () => subject.calls.map(call => call.sequence),
    });
  });

  it('should satisfy the one-shot fault-injection contract', async () => {
    const subject = new InMemoryMetricsCollector();
    await runFailInjectionContract({
      label: 'InMemoryMetricsCollector',
      makeError: () => ioError(),
      injectFailure: error => subject.failNext(error),
      callFallible: () => subject.record({ kind: 'gauge', name: 'g', value: 1 }),
    });
  });

  it('should satisfy the snapshot isolation contract', async () => {
    const subject = new InMemoryMetricsCollector();
    await runSnapshotIsolationContract({
      label: 'InMemoryMetricsCollector',
      produce: async () => {
        await subject.record({ kind: 'gauge', name: 'g', value: 1 });
      },
      readSnapshot: () => subject.metrics,
    });
  });
});
