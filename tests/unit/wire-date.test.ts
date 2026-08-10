import { describe, it } from 'bun:test';
import { Temporal } from '@js-temporal/polyfill';
import should from 'should';
import {
  formatWireDate,
  formatWireDateTime,
  formatWireDuration,
  formatWireTime,
  formatWireTimeZone,
  parseWireDate,
  parseWireDateTime,
  parseWireDuration,
  parseWireTime,
  parseWireTimeZone,
  type WireTimeZone,
} from '../../src/wire-date';

// ─── date · YYYY-MM-DD <-> Temporal.PlainDate ─────────────────────────────────────────────────────

describe('wire date codec', () => {
  it.each([
    { wire: '2020-02-29', label: 'a leap day' },
    { wire: '1999-12-31', label: 'a year boundary' },
    { wire: '2026-07-24', label: 'a typical date' },
  ])('should round-trip Temporal.PlainDate for $label ($wire)', ({ wire }) => {
    // Arrange
    const domain = parseWireDate(wire);

    // Act
    const formatted = formatWireDate(domain);
    const reparsed = parseWireDate(formatted);

    // Assert
    should(domain).be.instanceof(Temporal.PlainDate);
    should(formatted).equal(wire);
    should(reparsed.equals(domain)).be.true();
  });

  it.each([
    { wire: '2020-2-3', label: 'unpadded month and day' },
    { wire: '20-02-03', label: 'a two-digit year' },
    { wire: '2020/02/03', label: 'slash separators' },
    { wire: '2020-02-03T00:00:00', label: 'a trailing time component' },
    { wire: '', label: 'an empty string' },
  ])('should reject non-canonical wire date $label ($wire)', ({ wire }) => {
    // Arrange
    const act = () => parseWireDate(wire);

    // Act & Assert
    should(act).throw(RangeError, { message: /canonical YYYY-MM-DD/ });
  });

  it('should reject a canonically shaped but impossible calendar date', () => {
    // Arrange
    const wire = '2021-02-30';

    // Act
    const act = () => parseWireDate(wire);

    // Assert
    should(act).throw(RangeError, { message: /not a valid calendar date/ });
  });

  it('should reject a domain date that cannot be emitted as canonical YYYY-MM-DD', () => {
    // Arrange
    const domain = Temporal.PlainDate.from('2026-07-24[u-ca=hebrew]');

    // Act
    const act = () => formatWireDate(domain);

    // Assert
    should(act).throw(RangeError, { message: /cannot be represented/ });
  });
});

// ─── time · HH:mm:ss <-> Temporal.PlainTime ──────────────────────────────────────────────────────

describe('wire time codec', () => {
  it.each([
    { wire: '00:00:00', label: 'midnight' },
    { wire: '13:37:00', label: 'a whole minute' },
    { wire: '23:59:59', label: 'the last second of the day' },
  ])('should round-trip Temporal.PlainTime for $label ($wire)', ({ wire }) => {
    // Arrange
    const domain = parseWireTime(wire);

    // Act
    const formatted = formatWireTime(domain);
    const reparsed = parseWireTime(formatted);

    // Assert
    should(domain).be.instanceof(Temporal.PlainTime);
    should(formatted).equal(wire);
    should(reparsed.equals(domain)).be.true();
  });

  it('should reject a Temporal value carrying precision that HH:mm:ss cannot preserve', () => {
    // Arrange
    const domain = Temporal.PlainTime.from('01:02:03.456');

    // Act
    const act = () => formatWireTime(domain);

    // Assert
    should(act).throw(RangeError, { message: /whole-second precision/ });
  });

  it.each([
    { wire: '01:02', label: 'missing seconds' },
    { wire: '01:02:03.5', label: 'fractional seconds' },
    { wire: '01:02:03Z', label: 'a UTC designator' },
    { wire: '01:02:03+08:00', label: 'a numeric offset' },
    { wire: '1:2:3', label: 'unpadded fields' },
  ])('should reject non-canonical wire time $label ($wire)', ({ wire }) => {
    // Arrange
    const act = () => parseWireTime(wire);

    // Act & Assert
    should(act).throw(RangeError, { message: /canonical HH:mm:ss/ });
  });

  it('should reject a canonically shaped but out-of-range time', () => {
    // Arrange
    const wire = '25:00:00';

    // Act
    const act = () => parseWireTime(wire);

    // Assert
    should(act).throw(RangeError, { message: /not a valid time of day/ });
  });
});

// ─── datetime · RFC 3339 UTC instant <-> Temporal.Instant ────────────────────────────────────────

describe('wire datetime codec', () => {
  it.each([
    { wire: '1970-01-01T00:00:00Z', label: 'the epoch' },
    { wire: '2020-01-02T03:04:05Z', label: 'a typical instant' },
    { wire: '2026-07-24T23:59:59Z', label: 'the end of a day' },
    { wire: '2026-07-24T23:59:59.123456789Z', label: 'a nanosecond instant' },
  ])('should round-trip Temporal.Instant for $label ($wire)', ({ wire }) => {
    // Arrange
    const domain = parseWireDateTime(wire);

    // Act
    const formatted = formatWireDateTime(domain);
    const reparsed = parseWireDateTime(formatted);

    // Assert
    should(domain).be.instanceof(Temporal.Instant);
    should(formatted).equal(wire);
    should(reparsed.equals(domain)).be.true();
  });

  it('should preserve sub-second precision in a canonical UTC Z instant', () => {
    // Arrange
    const domain = Temporal.Instant.from('2020-01-02T03:04:05.123456789Z');

    // Act
    const formatted = formatWireDateTime(domain);

    // Assert
    should(formatted).equal('2020-01-02T03:04:05.123456789Z');
  });

  it.each([
    { wire: '2020-01-02T03:04:05', label: 'no UTC designator' },
    { wire: '2020-01-02T03:04:05+08:00', label: 'a non-UTC offset' },
    { wire: '2020-01-02 03:04:05Z', label: 'a space separator' },
    { wire: '2020-01-02T03:04Z', label: 'missing seconds' },
  ])('should reject non-canonical wire datetime $label ($wire)', ({ wire }) => {
    // Arrange
    const act = () => parseWireDateTime(wire);

    // Act & Assert
    should(act).throw(RangeError, { message: /canonical RFC 3339 UTC instant/ });
  });

  it('should reject a canonically shaped but impossible instant', () => {
    // Arrange
    const wire = '2020-13-01T00:00:00Z';

    // Act
    const act = () => parseWireDateTime(wire);

    // Assert
    should(act).throw(RangeError, { message: /not a valid instant/ });
  });

  it('should reject a non-minimal fractional-second spelling', () => {
    // Arrange
    const wire = '2020-01-02T03:04:05.120Z';

    // Act
    const act = () => parseWireDateTime(wire);

    // Assert
    should(act).throw(RangeError, { message: /canonical fractional precision/ });
  });

  it('should reject a domain instant outside the canonical RFC 3339 year range', () => {
    // Arrange
    const domain = Temporal.Instant.from('+010000-01-01T00:00:00Z');

    // Act
    const act = () => formatWireDateTime(domain);

    // Assert
    should(act).throw(RangeError, { message: /outside the canonical RFC 3339 year range/ });
  });
});

// ─── duration · ISO 8601 <-> Temporal.Duration ───────────────────────────────────────────────────

describe('wire duration codec', () => {
  it.each([
    { wire: 'PT0S', label: 'a zero duration' },
    { wire: 'P1DT2H', label: 'days and hours' },
    { wire: 'P1Y2M3DT4H5M6S', label: 'every field' },
    { wire: 'PT1.5S', label: 'fractional seconds' },
    { wire: '-P1D', label: 'a negative duration' },
  ])('should round-trip Temporal.Duration for $label ($wire)', ({ wire }) => {
    // Arrange
    const domain = parseWireDuration(wire);

    // Act
    const formatted = formatWireDuration(domain);
    const reparsed = parseWireDuration(formatted);

    // Assert
    should(domain).be.instanceof(Temporal.Duration);
    should(formatted).equal(wire);
    should(formatWireDuration(reparsed)).equal(formatted);
  });

  it.each([
    { wire: 'P', label: 'a bare designator' },
    { wire: 'abc', label: 'a non-duration string' },
    { wire: '1D', label: 'a missing period designator' },
    { wire: '', label: 'an empty string' },
  ])('should reject invalid wire duration $label ($wire)', ({ wire }) => {
    // Arrange
    const act = () => parseWireDuration(wire);

    // Act & Assert
    should(act).throw(RangeError, { message: /not a valid ISO 8601 duration/ });
  });

  it.each([
    { wire: 'p1dt2h', label: 'lowercase designators' },
    { wire: 'PT01H', label: 'zero-padded fields' },
    { wire: 'P0D', label: 'a non-minimal zero' },
  ])('should reject non-canonical wire duration $label ($wire)', ({ wire }) => {
    // Arrange
    const act = () => parseWireDuration(wire);

    // Act & Assert
    should(act).throw(RangeError, { message: /canonical Temporal spelling/ });
  });
});

// ─── timezone · IANA id <-> validated domain value ───────────────────────────────────────────────

describe('wire timezone codec', () => {
  it.each([
    { wire: 'UTC', label: 'UTC' },
    { wire: 'Asia/Singapore', label: 'a fixed-offset region' },
    { wire: 'America/New_York', label: 'a DST region' },
    { wire: 'Europe/London', label: 'another DST region' },
    { wire: 'Australia/Lord_Howe', label: 'a half-hour DST region' },
  ])('should round-trip a validated IANA identifier for $label ($wire)', ({ wire }) => {
    // Arrange
    const domain = parseWireTimeZone(wire);

    // Act
    const formatted = formatWireTimeZone(domain);
    const reparsed = parseWireTimeZone(formatted);

    // Assert
    should(formatted).equal(wire);
    should(formatWireTimeZone(reparsed)).equal(wire);
  });

  it.each([
    { wire: 'America/New_York', winter: '-05:00', summer: '-04:00' },
    { wire: 'Europe/London', winter: '+00:00', summer: '+01:00' },
  ])('should preserve a zone that genuinely observes DST ($wire)', ({ wire, winter, summer }) => {
    // Arrange
    const zone = parseWireTimeZone(wire);
    const winterInstant = parseWireDateTime('2021-01-01T12:00:00Z');
    const summerInstant = parseWireDateTime('2021-07-01T12:00:00Z');

    // Act
    const winterOffset = new Temporal.ZonedDateTime(winterInstant.epochNanoseconds, zone).offset;
    const summerOffset = new Temporal.ZonedDateTime(summerInstant.epochNanoseconds, zone).offset;

    // Assert
    should(winterOffset).equal(winter);
    should(summerOffset).equal(summer);
    should(winterOffset).not.equal(summerOffset);
  });

  it.each([
    { wire: 'Not/AZone', label: 'an unknown region' },
    { wire: '', label: 'an empty string' },
  ])('should reject an unknown wire timezone $label ($wire)', ({ wire }) => {
    // Arrange
    const act = () => parseWireTimeZone(wire);

    // Act & Assert
    should(act).throw(RangeError, { message: /not a known IANA time zone/ });
  });

  it('should reject a fixed numeric offset masquerading as a zone', () => {
    // Arrange
    const wire = '+01:00';

    // Act
    const act = () => parseWireTimeZone(wire);

    // Assert
    should(act).throw(RangeError, { message: /not a fixed offset/ });
  });

  it('should reject a non-canonical spelling of a real zone', () => {
    // Arrange
    const wire = 'asia/singapore';

    // Act
    const act = () => parseWireTimeZone(wire);

    // Assert
    should(act).throw(RangeError, { message: /canonical IANA id/ });
  });

  it('should expose the validated identifier as an assignable time-zone id', () => {
    // Arrange
    const zone: WireTimeZone = parseWireTimeZone('Asia/Singapore');
    const instant = parseWireDateTime('2021-01-01T00:00:00Z');

    // Act
    const zoned = new Temporal.ZonedDateTime(instant.epochNanoseconds, zone);

    // Assert
    should(zoned.timeZoneId).equal('Asia/Singapore');
  });

  it('should defensively reject an invalid branded timezone at the format boundary', () => {
    // Arrange
    const zone = 'Not/AZone' as WireTimeZone;

    // Act
    const act = () => formatWireTimeZone(zone);

    // Assert
    should(act).throw(RangeError, { message: /not a known IANA time zone/ });
  });
});
