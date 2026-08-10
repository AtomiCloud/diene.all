import { describe, it } from 'bun:test';
import type { LogRecord, MetricRecord, ProcessRequest } from '@atomicloud/diene.interfaces';
import {
  assertLoggerCalls,
  assertLogRecords,
  assertMetricRecords,
  assertMetricsCalls,
  assertSystemCalls,
  assertTerminalCalls,
  assertVfsCalls,
  assertVfsFiles,
  InMemoryLoggerSink,
  InMemoryMetricsCollector,
  InMemorySystem,
  InMemoryTerminal,
  InMemoryVirtualFileSystem,
  type LoggerCall,
  type MetricsCall,
  type TerminalCall,
  type VfsCall,
} from '@atomicloud/diene.interfaces/test-helper';
import { Ok } from '@atomicloud/diene.result';
import 'should';
import { expectAssertionError, expectNoThrow, expectOk } from './support/capture.js';

// Assert-the-asserter: every shipped assertion must pass on a known-good
// interaction and throw InterfaceAssertionError, with useful fields, on a
// known-bad one.

describe('assertSystemCalls', () => {
  const arrange = async (): Promise<InMemorySystem> => {
    const subject = new InMemorySystem([Ok({ exitCode: 0, stdout: '', stderr: '' })]);
    await expectOk(subject.execute({ executable: 'ls', arguments: ['-a'] }));
    return subject;
  };
  const expected: readonly ProcessRequest[] = [{ executable: 'ls', arguments: ['-a'] }];

  it('should pass on a matching sequence', async () => {
    const subject = await arrange();
    expectNoThrow(() => assertSystemCalls(subject, expected));
  });

  it('should throw a described InterfaceAssertionError on a mismatch', async () => {
    const subject = await arrange();
    const error = expectAssertionError(() => assertSystemCalls(subject, [{ executable: 'other' }]));
    error.label.should.eql('System calls');
    error.message.should.match(/System calls mismatch/);
    (error.expected as readonly ProcessRequest[]).should.eql([{ executable: 'other' }]);
    (error.actual as readonly ProcessRequest[]).should.eql([{ executable: 'ls', arguments: ['-a'] }]);
  });
});

describe('assertVfsCalls', () => {
  const arrange = async (): Promise<InMemoryVirtualFileSystem> => {
    const subject = new InMemoryVirtualFileSystem();
    await expectOk(subject.exists('/f'));
    return subject;
  };
  const expected: readonly VfsCall[] = [{ method: 'exists', path: '/f', sequence: 0 }];

  it('should pass on a matching sequence', async () => {
    const subject = await arrange();
    expectNoThrow(() => assertVfsCalls(subject, expected));
  });

  it('should throw on a mismatch', async () => {
    const subject = await arrange();
    const error = expectAssertionError(() =>
      assertVfsCalls(subject, [{ method: 'exists', path: '/other', sequence: 0 }]),
    );
    error.label.should.eql('VFS calls');
    error.message.should.match(/mismatch/);
  });
});

describe('assertVfsFiles', () => {
  const arrange = async (): Promise<InMemoryVirtualFileSystem> => {
    const subject = new InMemoryVirtualFileSystem();
    await expectOk(subject.writeFile('/f', new Uint8Array([1, 2])));
    return subject;
  };

  it('should pass on matching file bytes', async () => {
    const subject = await arrange();
    expectNoThrow(() => assertVfsFiles(subject, { '/f': new Uint8Array([1, 2]) }));
  });

  it('should throw on differing bytes', async () => {
    const subject = await arrange();
    const error = expectAssertionError(() => assertVfsFiles(subject, { '/f': new Uint8Array([9]) }));
    error.label.should.eql('VFS files');
  });
});

describe('assertTerminalCalls', () => {
  const arrange = async (): Promise<InMemoryTerminal> => {
    const subject = new InMemoryTerminal();
    await expectOk(subject.write({ channel: 'stdout', text: 'hi' }));
    return subject;
  };
  const expected: readonly TerminalCall[] = [
    { method: 'write', output: { channel: 'stdout', text: 'hi', newline: false }, sequence: 0 },
  ];

  it('should pass on a matching sequence', async () => {
    const subject = await arrange();
    expectNoThrow(() => assertTerminalCalls(subject, expected));
  });

  it('should throw on a mismatch', async () => {
    const subject = await arrange();
    const error = expectAssertionError(() =>
      assertTerminalCalls(subject, [
        { method: 'write', output: { channel: 'stderr', text: 'hi', newline: false }, sequence: 0 },
      ]),
    );
    error.label.should.eql('Terminal calls');
  });
});

describe('assertLogRecords', () => {
  const arrange = async (): Promise<InMemoryLoggerSink> => {
    const subject = new InMemoryLoggerSink();
    await expectOk(subject.emit({ level: 'info', message: 'hi' }));
    return subject;
  };
  const expected: readonly LogRecord[] = [{ level: 'info', message: 'hi' }];

  it('should pass on matching records', async () => {
    const subject = await arrange();
    expectNoThrow(() => assertLogRecords(subject, expected));
  });

  it('should throw on a mismatch', async () => {
    const subject = await arrange();
    const error = expectAssertionError(() => assertLogRecords(subject, [{ level: 'warn', message: 'hi' }]));
    error.label.should.eql('Log records');
  });
});

describe('assertLoggerCalls', () => {
  const arrange = async (): Promise<InMemoryLoggerSink> => {
    const subject = new InMemoryLoggerSink();
    await expectOk(subject.emit({ level: 'info', message: 'hi' }));
    await expectOk(subject.flush());
    return subject;
  };
  const expected: readonly LoggerCall[] = [
    { method: 'emit', record: { level: 'info', message: 'hi' }, sequence: 0 },
    { method: 'flush', sequence: 1 },
  ];

  it('should pass on a matching call log', async () => {
    const subject = await arrange();
    expectNoThrow(() => assertLoggerCalls(subject, expected));
  });

  it('should throw on a mismatch', async () => {
    const subject = await arrange();
    const error = expectAssertionError(() => assertLoggerCalls(subject, [{ method: 'flush', sequence: 0 }]));
    error.label.should.eql('Logger calls');
    error.message.should.match(/Logger calls mismatch/);
  });
});

describe('assertMetricRecords', () => {
  const arrange = async (): Promise<InMemoryMetricsCollector> => {
    const subject = new InMemoryMetricsCollector();
    await expectOk(subject.record({ kind: 'counter', name: 'hits', value: 1 }));
    return subject;
  };
  const expected: readonly MetricRecord[] = [{ kind: 'counter', name: 'hits', value: 1 }];

  it('should pass on matching metrics', async () => {
    const subject = await arrange();
    expectNoThrow(() => assertMetricRecords(subject, expected));
  });

  it('should throw on a mismatch', async () => {
    const subject = await arrange();
    const error = expectAssertionError(() => assertMetricRecords(subject, [{ kind: 'gauge', name: 'hits', value: 1 }]));
    error.label.should.eql('Metric records');
  });
});

describe('assertMetricsCalls', () => {
  const arrange = async (): Promise<InMemoryMetricsCollector> => {
    const subject = new InMemoryMetricsCollector();
    await expectOk(subject.record({ kind: 'counter', name: 'hits', value: 1 }));
    await expectOk(subject.flush());
    return subject;
  };
  const expected: readonly MetricsCall[] = [
    { method: 'record', metric: { kind: 'counter', name: 'hits', value: 1 }, sequence: 0 },
    { method: 'flush', sequence: 1 },
  ];

  it('should pass on a matching call log', async () => {
    const subject = await arrange();
    expectNoThrow(() => assertMetricsCalls(subject, expected));
  });

  it('should throw on a mismatch', async () => {
    const subject = await arrange();
    const error = expectAssertionError(() => assertMetricsCalls(subject, [{ method: 'flush', sequence: 0 }]));
    error.label.should.eql('Metrics calls');
    error.message.should.match(/Metrics calls mismatch/);
  });
});
