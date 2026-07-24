/**
 * Deferred app-handoff carrier encoding (C0 §7 "Carrier v1", Q-I48).
 *
 * The canonical carrier text is exactly `atomi-app-handoff:v1:<nonce>`. These
 * helpers are pure and environment-free so both the web (build) and mobile
 * (parse) clients can share them. `parseCarrier` returns `null` for any absent
 * or syntactically invalid carrier — absence is a normal outcome that falls
 * back to interactive login, not a fallible error.
 */

/** Carrier scheme version embedded in the canonical text. */
export const CARRIER_VERSION = 'v1';

/** Canonical carrier prefix; the nonce is appended verbatim. */
export const CARRIER_PREFIX = `atomi-app-handoff:${CARRIER_VERSION}:`;

/** Android Play Install Referrer form field name for the carrier. */
export const ANDROID_REFERRER_FIELD = 'app_handoff';

/** A base64url nonce is 32 random bytes → 43 unpadded characters. */
const NONCE_PATTERN = /^[A-Za-z0-9_-]{43}$/;

/** Build the canonical carrier text for a nonce. */
export function buildCarrier(nonce: string): string {
  return `${CARRIER_PREFIX}${nonce}`;
}

/**
 * Build the Android Play Install Referrer field carrying the nonce, as one
 * `application/x-www-form-urlencoded` field. Other campaign fields may be
 * concatenated around this one with `&`.
 */
export function buildAndroidReferrer(nonce: string): string {
  return new URLSearchParams({ [ANDROID_REFERRER_FIELD]: buildCarrier(nonce) }).toString();
}

/** Build the iOS clipboard payload — the canonical carrier text. */
export function buildIosClipboardPayload(nonce: string): string {
  return buildCarrier(nonce);
}

/**
 * Parse a canonical carrier text back to its nonce. ASCII leading/trailing
 * whitespace is trimmed. Returns `null` when the text is not a well-formed
 * carrier (wrong prefix or malformed nonce).
 */
export function parseCarrier(text: string): string | null {
  const trimmed = text.trim();
  if (!trimmed.startsWith(CARRIER_PREFIX)) {
    return null;
  }
  const nonce = trimmed.slice(CARRIER_PREFIX.length);
  return NONCE_PATTERN.test(nonce) ? nonce : null;
}

/**
 * Parse an Android Play Install Referrer form string, returning the carried
 * nonce or `null`. Zero or duplicate `app_handoff` fields are treated as absent
 * (C0 §7).
 */
export function parseAndroidReferrer(referrer: string): string | null {
  const values = new URLSearchParams(referrer).getAll(ANDROID_REFERRER_FIELD);
  if (values.length !== 1) {
    return null;
  }
  const [carrier] = values;
  return carrier === undefined ? null : parseCarrier(carrier);
}
