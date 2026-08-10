import { describe, it } from 'bun:test';
import { PortError } from '@atomicloud/diene.interfaces';
import { InMemorySystem, InterfaceAssertionError } from '@atomicloud/diene.interfaces/test-helper';
import 'should';
import { expectErr } from './support/capture.js';

describe('runtime identity across root and test-helper', () => {
  it('should recognize a test-helper-produced PortError as a root PortError instance', async () => {
    // Arrange - drive a mock into its own error branch
    const subject = new InMemorySystem();

    // Act
    const error = await expectErr(subject.execute({ executable: 'ls' }));

    // Assert - single source-mode module: instanceof holds against the root class
    error.should.be.instanceOf(PortError);
    (error instanceof PortError).should.be.true();
    error.should.be.instanceOf(Error);
    error._tag.should.eql('PortError');
  });
});

describe('InterfaceAssertionError', () => {
  it('should carry label, expected, actual, and a readable message', () => {
    // Act
    const error = new InterfaceAssertionError('Widget calls', { a: 1 }, { a: 2 });

    // Assert
    error.should.be.instanceOf(Error);
    error.name.should.eql('InterfaceAssertionError');
    error.label.should.eql('Widget calls');
    (error.expected as Record<string, number>).should.eql({ a: 1 });
    (error.actual as Record<string, number>).should.eql({ a: 2 });
    error.message.should.match(/Widget calls mismatch/);
    error.message.should.match(/Expected:/);
    error.message.should.match(/Actual:/);
  });

  it('should render Uint8Array payloads through the byte-normalizing comparator', () => {
    // Act - exercises the Uint8Array branch of the internal comparator
    const error = new InterfaceAssertionError('Bytes', new Uint8Array([1, 2]), new Uint8Array([3]));

    // Assert
    error.message.should.match(/"bytes":\[1,2\]/);
    error.message.should.match(/"bytes":\[3\]/);
  });
});
