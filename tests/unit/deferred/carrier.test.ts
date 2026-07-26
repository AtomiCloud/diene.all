import { describe, it } from 'bun:test';
import should from 'should';
import {
  ANDROID_REFERRER_FIELD,
  buildAndroidReferrer,
  buildCarrier,
  buildIosClipboardPayload,
  CARRIER_PREFIX,
  parseAndroidReferrer,
  parseCarrier,
} from '../../../src/lib/deferred/carrier';

const NONCE = 'abcDEF012_-abcDEF012_-abcDEF012_-abcDEF012_'; // 43 base64url chars

describe('deferred carrier', () => {
  it('builds the canonical carrier text', () => {
    // Arrange
    const input = NONCE;

    // Act
    const actual = buildCarrier(input);

    // Assert
    should(actual).equal(`atomi-app-handoff:v1:${input}`);
    should(actual.startsWith(CARRIER_PREFIX)).be.true();
  });

  it('round-trips the iOS clipboard payload', () => {
    // Arrange
    const input = buildIosClipboardPayload(NONCE);

    // Act
    const actual = parseCarrier(input);

    // Assert
    should(actual).equal(NONCE);
  });

  it('round-trips the Android referrer field', () => {
    // Arrange
    const input = buildAndroidReferrer(NONCE);

    // Act
    const actual = parseAndroidReferrer(input);

    // Assert
    should(input.startsWith(`${ANDROID_REFERRER_FIELD}=`)).be.true();
    should(actual).equal(NONCE);
  });

  it('parses the carrier when surrounded by other campaign fields', () => {
    // Arrange
    const input = `utm_source=play&${buildAndroidReferrer(NONCE)}&utm_medium=organic`;

    // Act
    const actual = parseAndroidReferrer(input);

    // Assert
    should(actual).equal(NONCE);
  });

  it('trims ASCII whitespace around a clipboard carrier', () => {
    // Arrange
    const input = `  \t${buildCarrier(NONCE)}\n `;

    // Act
    const actual = parseCarrier(input);

    // Assert
    should(actual).equal(NONCE);
  });

  it('rejects a carrier with the wrong prefix', () => {
    // Arrange / Act / Assert
    should(parseCarrier(`atomi-app-handoff:v2:${NONCE}`)).be.null();
    should(parseCarrier(NONCE)).be.null();
  });

  it('rejects a carrier whose nonce is malformed', () => {
    // Arrange / Act / Assert
    should(parseCarrier(`${CARRIER_PREFIX}too-short`)).be.null();
    should(parseCarrier(`${CARRIER_PREFIX}${NONCE}!`)).be.null();
  });

  it('treats a missing android field as absent', () => {
    // Arrange
    const input = 'utm_source=play';

    // Act
    const actual = parseAndroidReferrer(input);

    // Assert
    should(actual).be.null();
  });

  it('treats duplicate android fields as absent', () => {
    // Arrange
    const input = `${buildAndroidReferrer(NONCE)}&${buildAndroidReferrer(NONCE)}`;

    // Act
    const actual = parseAndroidReferrer(input);

    // Assert
    should(actual).be.null();
  });
});
