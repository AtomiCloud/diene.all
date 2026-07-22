/**
 * JSON-serialisable tagged-object wire contract for the Result/Option monads.
 *
 * This is the deliberate Bun adaptation of Dart's tagged-array form: the wire
 * is an idiomatic discriminated object `{ kind, value | error }` so it survives
 * `JSON.stringify`/`JSON.parse` round-trips unchanged.
 */

/** Wire form of a {@link Result}: `{kind:'ok',value}` or `{kind:'err',error}`. */
export type ResultSerial<VO = unknown, EO = unknown> = { kind: 'ok'; value: VO } | { kind: 'err'; error: EO };

/** Wire form of an {@link Option}: `{kind:'some',value}` or `{kind:'none'}`. */
export type OptionSerial<VO = unknown> = { kind: 'some'; value: VO } | { kind: 'none' };

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

/**
 * Validates a raw Result wire value and narrows it to {@link ResultSerial}.
 *
 * Throws {@link TypeError} on a malformed wire: a non-object, an unknown
 * `kind`, or a variant missing its `value`/`error` payload key.
 */
export function readResultWire(serial: ResultSerial): ResultSerial {
  if (!isRecord(serial)) {
    throw new TypeError('Result wire value must be an object.');
  }

  const kind = serial.kind;
  if (kind === 'ok') {
    if (!('value' in serial)) {
      throw new TypeError('Result ok wire value must carry a value.');
    }
    return serial;
  }
  if (kind === 'err') {
    if (!('error' in serial)) {
      throw new TypeError('Result err wire value must carry an error.');
    }
    return serial;
  }

  throw new TypeError(`Result wire value has an unknown kind: ${String(kind)}.`);
}

/**
 * Validates a raw Option wire value and narrows it to {@link OptionSerial}.
 *
 * Throws {@link TypeError} on a malformed wire: a non-object, an unknown
 * `kind`, a `some` missing its `value`, or a `none` carrying a `value`.
 */
export function readOptionWire(serial: OptionSerial): OptionSerial {
  if (!isRecord(serial)) {
    throw new TypeError('Option wire value must be an object.');
  }

  const kind = serial.kind;
  if (kind === 'some') {
    if (!('value' in serial)) {
      throw new TypeError('Option some wire value must carry a value.');
    }
    return serial;
  }
  if (kind === 'none') {
    if ('value' in serial) {
      throw new TypeError('Option none wire value must not carry a value.');
    }
    return serial;
  }

  throw new TypeError(`Option wire value has an unknown kind: ${String(kind)}.`);
}
