import { describe, it } from 'bun:test';
import { portError, type TerminalChannel, type TerminalError } from '@atomicloud/diene.interfaces';
import { InMemoryTerminal } from '@atomicloud/diene.interfaces/test-helper';
import 'should';
import { runFailInjectionContract, runSequenceContract, runSnapshotIsolationContract } from './contract/behaviours.js';
import { expectErr, expectOk } from './support/capture.js';

const ioError = (operation: string): TerminalError => portError('terminal', 'io', operation, 'boom');
const write = { channel: 'stdout', text: 'hi' } as const;

describe('InMemoryTerminal write', () => {
  it('should normalize and record a valid write', async () => {
    const subject = new InMemoryTerminal();
    await expectOk(subject.write({ channel: 'stderr', text: 'x', newline: true }));
    subject.calls[0]?.method.should.eql('write');
    if (subject.calls[0]?.method === 'write') {
      subject.calls[0].output.should.eql({ channel: 'stderr', text: 'x', newline: true });
    }
  });

  it('should reject an invalid channel', async () => {
    const subject = new InMemoryTerminal();
    const error = await expectErr(subject.write({ channel: 'bad' as unknown as TerminalChannel, text: 'x' }));
    error.details.should.eql({ field: 'channel' });
  });

  it('should surface a closed terminal ahead of any injected failure', async () => {
    // Arrange - both closed and armed-to-fail
    const subject = new InMemoryTerminal();
    subject.failNext(ioError('write'));
    subject.close();

    // Act - closed wins; the injected failure is not consumed
    (await expectErr(subject.write(write))).code.should.eql('closed');
  });

  it('should surface an injected failure while open', async () => {
    const subject = new InMemoryTerminal();
    subject.failNext(ioError('write'));
    (await expectErr(subject.write(write))).code.should.eql('io');
  });
});

describe('InMemoryTerminal readLine', () => {
  it('should reject invalid setup values before they can fabricate terminal output', async () => {
    (() => new InMemoryTerminal([42 as unknown as string])).should.throw(TypeError);
    (() => new InMemoryTerminal(null as unknown as readonly string[])).should.throw(TypeError);
    (() => new InMemoryTerminal([], 'yes' as unknown as boolean)).should.throw(TypeError);

    const subject = new InMemoryTerminal();
    (() => subject.enqueue(42 as unknown as string)).should.throw(TypeError);
    const drained = await expectOk(subject.readLine());
    (drained === null).should.be.true();
  });

  it('should default the interactive flag to false and take no argument', async () => {
    const subject = new InMemoryTerminal();
    subject.interactive.should.be.false();
    await expectOk(subject.readLine());
    subject.calls[0]?.method.should.eql('readLine');
    if (subject.calls[0]?.method === 'readLine') subject.calls[0].input.should.eql({});
  });

  it('should drain queued input then return null, honoring constructor seed', async () => {
    const subject = new InMemoryTerminal(['first'], true);
    subject.interactive.should.be.true();
    subject.enqueue('second');
    ((await expectOk(subject.readLine({ prompt: 'p' }))) ?? '').should.eql('first');
    ((await expectOk(subject.readLine())) ?? '').should.eql('second');
    // draining past the queue yields null — compare by identity, not `.should` on null
    const drained = await expectOk(subject.readLine());
    (drained === null).should.be.true();
  });

  it('should reject a non-string prompt', async () => {
    const subject = new InMemoryTerminal();
    const error = await expectErr(subject.readLine({ prompt: 5 as unknown as string }));
    error.details.should.eql({ field: 'prompt' });
  });

  it('should surface a closed terminal', async () => {
    const subject = new InMemoryTerminal();
    subject.close();
    (await expectErr(subject.readLine())).code.should.eql('closed');
  });

  it('should surface an injected failure while open', async () => {
    const subject = new InMemoryTerminal();
    subject.failNext(ioError('readLine'));
    (await expectErr(subject.readLine())).code.should.eql('io');
  });
});

describe('InMemoryTerminal recorded state', () => {
  it('should expose frozen, independent copies of write and read calls', async () => {
    const subject = new InMemoryTerminal(['line']);
    await expectOk(subject.write(write));
    await expectOk(subject.readLine({ prompt: 'p' }));

    const calls = subject.calls;
    calls.should.have.length(2);
    Object.isFrozen(calls[0]).should.be.true();
    (subject.calls[0] === calls[0]).should.be.false();
  });

  it('should satisfy the sequence contract', async () => {
    const subject = new InMemoryTerminal();
    await runSequenceContract({
      label: 'InMemoryTerminal',
      record: async () => {
        await subject.readLine();
      },
      sequences: () => subject.calls.map(call => call.sequence),
    });
  });

  it('should satisfy the one-shot fault-injection contract', async () => {
    const subject = new InMemoryTerminal();
    await runFailInjectionContract({
      label: 'InMemoryTerminal',
      makeError: () => ioError('write'),
      injectFailure: error => subject.failNext(error),
      callFallible: () => subject.write(write),
    });
  });

  it('should satisfy the snapshot isolation contract', async () => {
    const subject = new InMemoryTerminal();
    await runSnapshotIsolationContract({
      label: 'InMemoryTerminal',
      produce: async () => {
        await subject.readLine();
      },
      readSnapshot: () => subject.calls,
    });
  });
});
