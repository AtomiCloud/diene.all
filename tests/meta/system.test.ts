import { describe, it } from 'bun:test';
import { type ProcessOutput, type ProcessRequest, portError } from '@atomicloud/diene.interfaces';
import { InMemorySystem } from '@atomicloud/diene.interfaces/test-helper';
import { Err, Ok, type Result } from '@atomicloud/diene.result';
import 'should';
import { runSequenceContract, runSnapshotIsolationContract } from './contract/behaviours.js';
import { expectErr, expectOk } from './support/capture.js';

const output = (over: Partial<ProcessOutput> = {}): ProcessOutput =>
  Object.freeze({ exitCode: 0, stdout: '', stderr: '', ...over });

const okOutcome = (over: Partial<ProcessOutput> = {}): Result<ProcessOutput, never> => Ok(output(over));

describe('InMemorySystem', () => {
  it('should return the queued outcome and record the validated request', async () => {
    // Arrange - outcomes provided via the constructor
    const subject = new InMemorySystem([okOutcome({ exitCode: 2, stdout: 'hi' })]);
    const request: ProcessRequest = { executable: 'ls', arguments: ['-a'] };

    // Act
    const actual = await expectOk(subject.execute(request));

    // Assert
    actual.should.eql({ exitCode: 2, stdout: 'hi', stderr: '' });
    subject.calls.should.have.length(1);
    subject.calls[0]?.method.should.eql('execute');
    subject.calls[0]?.sequence.should.eql(0);
    subject.calls[0]?.request.should.eql({ executable: 'ls', arguments: ['-a'] });
  });

  it('should reject an invalid request without recording a call', async () => {
    // Arrange
    const subject = new InMemorySystem();

    // Act
    const error = await expectErr(subject.execute({ executable: '' }));

    // Assert - validation rejection happens before the call is recorded
    error.code.should.eql('invalid-input');
    subject.calls.should.have.length(0);
  });

  it('should surface unexpected-call when no outcome is queued', async () => {
    // Arrange
    const subject = new InMemorySystem();

    // Act
    const error = await expectErr(subject.execute({ executable: 'ls' }));

    // Assert - the call is still recorded even though it had no scripted outcome
    error.code.should.eql('unexpected-call');
    error.details.should.eql({ executable: 'ls' });
    subject.calls.should.have.length(1);
  });

  it('should pass a queued error outcome straight through', async () => {
    // Arrange
    const failure = portError('system', 'io', 'execute', 'spawn failed');
    const subject = new InMemorySystem([Err(failure)]);

    // Act
    const error = await expectErr(subject.execute({ executable: 'ls' }));

    // Assert
    (error === failure).should.be.true();
  });

  it('should validate a queued success outcome and reject a malformed one', async () => {
    // Arrange - a structurally invalid ProcessOutput is queued
    const subject = new InMemorySystem([okOutcome({ exitCode: 1.5 })]);

    // Act
    const error = await expectErr(subject.execute({ executable: 'ls' }));

    // Assert
    error.code.should.eql('invalid-input');
    error.message.should.match(/integer exit code/);
  });

  it('should append outcomes with enqueue in FIFO order', async () => {
    // Arrange
    const subject = new InMemorySystem();
    subject.enqueue(okOutcome({ stdout: 'first' }));
    subject.enqueue(okOutcome({ stdout: 'second' }));

    // Act
    const a = await expectOk(subject.execute({ executable: 'a' }));
    const b = await expectOk(subject.execute({ executable: 'b' }));

    // Assert
    a.stdout.should.eql('first');
    b.stdout.should.eql('second');
    subject.calls.map(call => call.request.executable).should.eql(['a', 'b']);
  });

  it('should hand back frozen, defensively copied recorded requests', async () => {
    // Arrange
    const subject = new InMemorySystem([okOutcome()]);
    await subject.execute({ executable: 'ls', environment: { A: '1' } });

    // Act
    const snapshot = subject.calls;

    // Assert - each read is a fresh frozen copy
    Object.isFrozen(snapshot[0]).should.be.true();
    Object.isFrozen(snapshot[0]?.request).should.be.true();
    (subject.calls[0] === snapshot[0]).should.be.false();
  });

  it('should satisfy the deterministic sequence contract', async () => {
    const subject = new InMemorySystem();
    await runSequenceContract({
      label: 'InMemorySystem',
      record: async () => {
        subject.enqueue(okOutcome());
        await subject.execute({ executable: 'ls' });
      },
      sequences: () => subject.calls.map(call => call.sequence),
    });
  });

  it('should satisfy the snapshot isolation contract', async () => {
    const subject = new InMemorySystem([okOutcome()]);
    await runSnapshotIsolationContract({
      label: 'InMemorySystem',
      produce: async () => {
        await subject.execute({ executable: 'ls' });
      },
      readSnapshot: () => subject.calls,
    });
  });
});
