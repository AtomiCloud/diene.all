import { Temporal } from '@js-temporal/polyfill';

// ─── WIRE DATE CODECS ───────────────────────────────────────────────────────────────────────────
// Explicit parse/format codecs between the C0 canonical wire forms and Temporal domain values.
// Every canonical form has a `parseWire*` (string -> Temporal) and a `formatWire*` (Temporal ->
// string). Parsing rejects any non-canonical spelling with a `RangeError` carrying a useful
// message; formatting always emits the single canonical spelling.

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const TIME_PATTERN = /^\d{2}:\d{2}:\d{2}$/;
const INSTANT_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z$/;
const OFFSET_ZONE_PATTERN = /^[+-]\d{2}:\d{2}$/;

// ─── date · YYYY-MM-DD <-> Temporal.PlainDate ─────────────────────────────────────────────────────

export function parseWireDate(input: string): Temporal.PlainDate {
  if (!DATE_PATTERN.test(input)) {
    throw new RangeError(`wire date must be canonical YYYY-MM-DD, received "${input}"`);
  }
  try {
    return Temporal.PlainDate.from(input, { overflow: 'reject' });
  } catch (cause) {
    throw new RangeError(`wire date "${input}" is not a valid calendar date`, { cause });
  }
}

export function formatWireDate(date: Temporal.PlainDate): string {
  const formatted = date.toString();
  if (!DATE_PATTERN.test(formatted)) {
    throw new RangeError('wire date domain value cannot be represented as canonical YYYY-MM-DD');
  }
  return formatted;
}

// ─── time · HH:mm:ss <-> Temporal.PlainTime ──────────────────────────────────────────────────────

export function parseWireTime(input: string): Temporal.PlainTime {
  if (!TIME_PATTERN.test(input)) {
    throw new RangeError(
      `wire time must be canonical HH:mm:ss with seconds and no fraction or offset, received "${input}"`,
    );
  }
  try {
    return Temporal.PlainTime.from(input, { overflow: 'reject' });
  } catch (cause) {
    throw new RangeError(`wire time "${input}" is not a valid time of day`, { cause });
  }
}

export function formatWireTime(time: Temporal.PlainTime): string {
  if (time.millisecond !== 0 || time.microsecond !== 0 || time.nanosecond !== 0) {
    throw new RangeError('wire time domain value must have whole-second precision');
  }
  return time.toString({ smallestUnit: 'second' });
}

// ─── datetime · RFC 3339 UTC instant <-> Temporal.Instant ────────────────────────────────────────

export function parseWireDateTime(input: string): Temporal.Instant {
  if (!INSTANT_PATTERN.test(input)) {
    throw new RangeError(
      `wire datetime must be a canonical RFC 3339 UTC instant (YYYY-MM-DDTHH:mm:ssZ), received "${input}"`,
    );
  }
  try {
    const instant = Temporal.Instant.from(input);
    if (instant.toString() !== input) {
      throw new RangeError(`wire datetime must use canonical fractional precision, received "${input}"`);
    }
    return instant;
  } catch (cause) {
    if (cause instanceof RangeError && cause.message.includes('canonical fractional precision')) {
      throw cause;
    }
    throw new RangeError(`wire datetime "${input}" is not a valid instant`, { cause });
  }
}

export function formatWireDateTime(instant: Temporal.Instant): string {
  const formatted = instant.toString();
  if (!INSTANT_PATTERN.test(formatted)) {
    throw new RangeError('wire datetime domain value is outside the canonical RFC 3339 year range');
  }
  return formatted;
}

// ─── duration · ISO 8601 <-> Temporal.Duration ───────────────────────────────────────────────────

export function parseWireDuration(input: string): Temporal.Duration {
  let duration: Temporal.Duration;
  try {
    duration = Temporal.Duration.from(input);
  } catch (cause) {
    throw new RangeError(`wire duration "${input}" is not a valid ISO 8601 duration`, { cause });
  }
  // Require the canonical Temporal serialization so non-canonical spellings (lowercase designators,
  // zero-padded fields, non-minimal units) never round-trip silently.
  const canonical = duration.toString();
  if (canonical !== input) {
    throw new RangeError(`wire duration must be the canonical Temporal spelling "${canonical}", received "${input}"`);
  }
  return duration;
}

export function formatWireDuration(duration: Temporal.Duration): string {
  return duration.toString();
}

// ─── timezone · IANA id <-> validated domain value ───────────────────────────────────────────────
// Polyfill 0.5.1 dropped `Temporal.TimeZone`, so the domain value is a branded IANA identifier that
// has been validated (and confirmed canonical) through `Temporal.ZonedDateTime`. The brand keeps the
// validated id distinct from an arbitrary string while remaining usable anywhere Temporal accepts a
// time-zone id.

declare const wireTimeZoneBrand: unique symbol;
export type WireTimeZone = string & { readonly [wireTimeZoneBrand]: 'WireTimeZone' };

export function parseWireTimeZone(input: string): WireTimeZone {
  let canonical: string;
  try {
    // Constructing a ZonedDateTime validates the id and normalizes it to its canonical spelling.
    canonical = new Temporal.ZonedDateTime(0n, input).timeZoneId;
  } catch (cause) {
    throw new RangeError(`wire timezone "${input}" is not a known IANA time zone`, { cause });
  }
  if (OFFSET_ZONE_PATTERN.test(canonical)) {
    throw new RangeError(`wire timezone must be a named IANA identifier, not a fixed offset, received "${input}"`);
  }
  if (canonical !== input) {
    throw new RangeError(`wire timezone must be the canonical IANA id "${canonical}", received "${input}"`);
  }
  return canonical as WireTimeZone;
}

export function formatWireTimeZone(zone: WireTimeZone): string {
  return parseWireTimeZone(zone);
}
