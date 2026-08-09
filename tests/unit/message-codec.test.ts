import { describe, it } from 'bun:test';
import should from 'should';
import {
  decodeAutoClaimResponse,
  decodeReadGroupResponse,
  decodeStreamEntries,
  decodeWorkerMessage,
  encodeWorkerMessage,
} from '../../src/lib/message-codec';

const message = {
  createdAt: '2026-07-25T06:30:00Z',
  id: '11d8ab19-cdc7-4bc4-a178-70a352c352e8',
  payload: 'hello',
};

describe('worker message codec', () => {
  it('should encode and decode a validated worker message', () => {
    // Arrange
    const encoded = encodeWorkerMessage(message);

    // Act
    const actual = decodeWorkerMessage(encoded);

    // Assert
    should(actual).deepEqual(message);
  });

  it('should reject malformed JSON input', () => {
    // Arrange
    const input = 'not-json';

    // Act
    const actual = () => decodeWorkerMessage(input);

    // Assert
    should(actual).throw();
  });
});

describe('Redis stream response codec', () => {
  it('should return no messages for an empty blocking read', () => {
    // Arrange
    const input = null;

    // Act
    const actual = decodeReadGroupResponse(input);

    // Assert
    should(actual).deepEqual([]);
  });

  it('should decode read-group stream entries', () => {
    // Arrange
    const input = [['events', [['1-0', ['other', 'ignored', 'payload', 'one']]]]];

    // Act
    const actual = decodeReadGroupResponse(input);

    // Assert
    should(actual).deepEqual([{ id: '1-0', payload: 'one' }]);
  });

  it('should decode auto-claimed stream entries', () => {
    // Arrange
    const input = ['0-0', [['2-0', ['payload', 'two']]], []];

    // Act
    const actual = decodeAutoClaimResponse(input);

    // Assert
    should(actual).deepEqual([{ id: '2-0', payload: 'two' }]);
  });

  it('should reject an entry without a payload field', () => {
    // Arrange
    const input = [['3-0', ['other', 'value']]];

    // Act
    const actual = () => decodeStreamEntries(input);

    // Assert
    should(actual).throw();
  });
});
