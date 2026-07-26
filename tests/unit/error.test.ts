import { describe, it } from 'bun:test';
import { PortError, type PortErrorDetails, portError } from '@atomicloud/diene.interfaces';
import 'should';

describe('PortError', () => {
  it('should carry the tag, name, and constructor fields', () => {
    // Arrange
    const details: PortErrorDetails = { field: 'executable', attempts: 2 };

    // Act
    const subject = portError('system', 'invalid-input', 'execute', 'boom', details);

    // Assert
    subject.should.be.instanceOf(Error);
    subject.should.be.instanceOf(PortError);
    subject._tag.should.eql('PortError');
    subject.name.should.eql('PortError');
    subject.port.should.eql('system');
    subject.code.should.eql('invalid-input');
    subject.operation.should.eql('execute');
    subject.message.should.eql('boom');
    subject.details.should.eql({ field: 'executable', attempts: 2 });
  });

  it('should freeze a defensive copy of the details record', () => {
    // Arrange
    const source: Record<string, unknown> = { field: 'name' };

    // Act
    const subject = portError('metrics', 'io', 'record', 'msg', source);
    source.field = 'mutated';

    // Assert - snapshot is frozen and detached from the caller's object
    Object.isFrozen(subject.details).should.be.true();
    subject.details.should.eql({ field: 'name' });
  });

  it('should default details to an empty frozen record when omitted', () => {
    // Act
    const subject = portError('vfs', 'not-found', 'readFile', 'missing');

    // Assert
    Object.isFrozen(subject.details).should.be.true();
    subject.details.should.eql({});
  });

  it('should construct directly with the same identity as the factory', () => {
    // Act
    const direct = new PortError('terminal', 'closed', 'write', 'closed stream');

    // Assert - source-mode single-module identity: instanceof holds both ways
    direct.should.be.instanceOf(PortError);
    (direct instanceof PortError).should.be.true();
    direct.port.should.eql('terminal');
    direct.details.should.eql({});
  });
});
