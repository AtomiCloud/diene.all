import { describe, it } from 'bun:test';
import {
  type TerminalChannel,
  type TerminalRead,
  type TerminalWrite,
  validateTerminalRead,
  validateTerminalWrite,
} from '@atomicloud/diene.interfaces';
import 'should';
import { expectErr, expectOk } from './support/result.js';

describe('validateTerminalWrite', () => {
  it.each([
    ['explicit true', true, true],
    ['explicit false', false, false],
    ['omitted defaults to false', undefined, false],
  ])('should normalize newline (%s)', async (_label, newline, expected) => {
    // Act
    const actual = await expectOk(validateTerminalWrite({ channel: 'stdout', text: 'hi', newline } as TerminalWrite));

    // Assert
    actual.should.eql({ channel: 'stdout', text: 'hi', newline: expected });
    Object.isFrozen(actual).should.be.true();
  });

  it('should accept the stderr channel', async () => {
    const actual = await expectOk(validateTerminalWrite({ channel: 'stderr', text: '' }));
    actual.channel.should.eql('stderr');
  });

  it.each([
    ['null', null as unknown as TerminalWrite],
    ['a primitive', 2 as unknown as TerminalWrite],
  ])('should reject a non-object output (%s)', async (_label, output) => {
    const error = await expectErr(validateTerminalWrite(output));
    error.port.should.eql('terminal');
    error.operation.should.eql('write');
    error.details.should.eql({ field: 'output' });
  });

  it('should reject an invalid channel', async () => {
    const error = await expectErr(
      validateTerminalWrite({ channel: 'stdlog' as unknown as TerminalChannel, text: 'x' }),
    );
    error.details.should.eql({ field: 'channel' });
  });

  it('should reject non-string text', async () => {
    const error = await expectErr(validateTerminalWrite({ channel: 'stdout', text: 5 as unknown as string }));
    error.details.should.eql({ field: 'text' });
  });

  it('should reject a non-boolean newline', async () => {
    const error = await expectErr(
      validateTerminalWrite({ channel: 'stdout', text: 'x', newline: 'yes' as unknown as boolean }),
    );
    error.details.should.eql({ field: 'newline' });
  });
});

describe('validateTerminalRead', () => {
  it('should default to an empty read when called with no argument', async () => {
    // Act
    const actual = await expectOk(validateTerminalRead());

    // Assert
    actual.should.eql({});
    Object.isFrozen(actual).should.be.true();
  });

  it('should retain a provided prompt', async () => {
    const actual = await expectOk(validateTerminalRead({ prompt: 'name?' }));
    actual.should.eql({ prompt: 'name?' });
  });

  it.each([
    ['null', null as unknown as TerminalRead],
    ['a primitive', 2 as unknown as TerminalRead],
  ])('should reject a non-object input (%s)', async (_label, input) => {
    const error = await expectErr(validateTerminalRead(input));
    error.operation.should.eql('readLine');
    error.details.should.eql({ field: 'input' });
  });

  it('should reject a non-string prompt', async () => {
    const error = await expectErr(validateTerminalRead({ prompt: 5 as unknown as string }));
    error.details.should.eql({ field: 'prompt' });
  });
});
