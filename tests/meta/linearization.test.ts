import { describe, it } from 'bun:test';
import { portError } from '@atomicloud/diene.interfaces';
import {
  InMemoryLoggerSink,
  InMemoryTerminal,
  InMemoryVirtualFileSystem,
} from '@atomicloud/diene.interfaces/test-helper';
import 'should';
import { expectErr, expectOk } from './support/capture.js';

// The mocks linearize at invocation: the synchronous `check*` core records the
// call and resolves the state transition the instant the method is invoked, even
// though the returned Result is awaited later. A mutation issued after the call
// must never be observed by that already-issued operation.

describe('mock linearization', () => {
  it('should record a terminal read synchronously, before the Result is awaited', async () => {
    // Arrange
    const subject = new InMemoryTerminal(['a']);

    // Act - issue the operation but do NOT await it yet
    const pending = subject.readLine({ prompt: 'p' });

    // Assert - the call is already recorded synchronously
    subject.calls.should.have.length(1);
    subject.calls[0]?.method.should.eql('readLine');

    // A later enqueue/close cannot change the already-issued read
    subject.enqueue('late');
    subject.close();
    ((await expectOk(pending)) ?? '').should.eql('a');

    // ...but the NEXT read observes the close that happened before it
    (await expectErr(subject.readLine())).code.should.eql('closed');
  });

  it('should fix a terminal write outcome at call time despite a later close', async () => {
    const subject = new InMemoryTerminal();

    const pending = subject.write({ channel: 'stdout', text: 'hi' });
    subject.calls.should.have.length(1);
    subject.close();

    // the write was issued while open, so its Result stays Ok
    await expectOk(pending);
  });

  it('should fix a VFS read outcome before a later failNext takes effect', async () => {
    // Arrange
    const subject = new InMemoryVirtualFileSystem();
    await expectOk(subject.writeFile('/f', new Uint8Array([1])));

    // Act - issue exists(), then arm a failure afterwards
    const pending = subject.exists('/f');
    subject.failNext(portError('vfs', 'io', 'exists', 'late fault'));

    // Assert - the issued read is unaffected; the armed failure hits the next call
    (await expectOk(pending)).should.be.true();
    (await expectErr(subject.exists('/f'))).code.should.eql('io');
  });

  it('should retain an emitted log record synchronously, unaffected by a later failNext', async () => {
    const subject = new InMemoryLoggerSink();

    const pending = subject.emit({ level: 'info', message: 'm' });
    // recorded synchronously at invocation
    subject.calls.should.have.length(1);
    subject.failNext(portError('logging', 'io', 'emit', 'late fault'));

    await expectOk(pending);
    subject.records.should.have.length(1);
    // the armed failure only bites the following emit
    (await expectErr(subject.emit({ level: 'info', message: 'n' }))).code.should.eql('io');
  });
});
