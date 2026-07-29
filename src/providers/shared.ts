import { createHash, createHmac, timingSafeEqual } from 'node:crypto';
import type { ProviderMetadata, ProviderName, VerificationHeaders, VerifiedWebhook } from './types.ts';
import { VerificationError } from './types.ts';

const utf8Decoder = new TextDecoder('utf-8', { fatal: true });
const utf8Encoder = new TextEncoder();

const getHeader = (headers: VerificationHeaders, expectedName: string): string | undefined => {
  const normalizedExpectedName = expectedName.toLowerCase();

  for (const [name, value] of Object.entries(headers)) {
    if (name.toLowerCase() === normalizedExpectedName) {
      return value;
    }
  }

  return undefined;
};

export const requireHeader = (headers: VerificationHeaders, name: string): string => {
  const value = getHeader(headers, name);
  if (value === undefined || value.length === 0) {
    throw new VerificationError('missing_header', `Missing ${name} header`);
  }
  return value;
};

export const decodeBody = (rawBody: Uint8Array): string => {
  try {
    return utf8Decoder.decode(rawBody);
  } catch (error) {
    throw new VerificationError('malformed_payload', 'Webhook body is not valid UTF-8', { cause: error });
  }
};

export const parseJson = (rawBody: Uint8Array): Record<string, unknown> => {
  let parsed: unknown;
  try {
    parsed = JSON.parse(decodeBody(rawBody));
  } catch (error) {
    if (error instanceof VerificationError) {
      throw error;
    }
    throw new VerificationError('malformed_payload', 'Webhook body is not valid JSON', { cause: error });
  }

  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new VerificationError('malformed_payload', 'Webhook body must be a JSON object');
  }
  return parsed as Record<string, unknown>;
};

export const stringField = (value: Record<string, unknown>, field: string): string | undefined => {
  const candidate = value[field];
  return typeof candidate === 'string' && candidate.length > 0 ? candidate : undefined;
};

export const numberField = (value: Record<string, unknown>, field: string): number | undefined => {
  const candidate = value[field];
  return typeof candidate === 'number' && Number.isFinite(candidate) ? candidate : undefined;
};

export const parseTimestamp = (value: string | undefined): number | undefined => {
  if (value === undefined) {
    return undefined;
  }
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) ? timestamp : undefined;
};

export const assertSecrets = (secrets: readonly string[]): void => {
  if (secrets.length === 0 || secrets.some(secret => secret.length === 0)) {
    throw new VerificationError('invalid_configuration', 'At least one non-empty verification secret is required');
  }
};

export const hmacSha256 = (secret: string, parts: readonly (string | Uint8Array)[]): Uint8Array => {
  const hmac = createHmac('sha256', secret);
  for (const part of parts) {
    hmac.update(part);
  }
  return hmac.digest();
};

const decodeHex = (value: string, expectedBytes: number): Uint8Array | undefined => {
  if (value.length !== expectedBytes * 2 || !/^[\da-f]+$/i.test(value)) {
    return undefined;
  }
  return Buffer.from(value, 'hex');
};

export const constantTimeHexEqual = (expected: Uint8Array, submittedHex: string): boolean => {
  const submitted = decodeHex(submittedHex, expected.byteLength);
  return submitted !== undefined && timingSafeEqual(expected, submitted);
};

export const constantTimeStringEqual = (expected: string, submitted: string): boolean => {
  const expectedDigest = createHash('sha256').update(utf8Encoder.encode(expected)).digest();
  const submittedDigest = createHash('sha256').update(utf8Encoder.encode(submitted)).digest();
  return timingSafeEqual(expectedDigest, submittedDigest);
};

const fallbackDedupId = (provider: ProviderName, rawBody: Uint8Array, signature: string): string => {
  const digest = createHash('sha256')
    .update(provider)
    .update('\0')
    .update(rawBody)
    .update('\0')
    .update(signature)
    .digest('hex');
  return `sha256:${digest}`;
};

export const verifiedWebhook = (
  provider: ProviderName,
  rawBody: Uint8Array,
  signature: string,
  metadata: ProviderMetadata,
): VerifiedWebhook => ({
  provider,
  dedupId: metadata.eventId ?? fallbackDedupId(provider, rawBody, signature),
  signatureMaterial: signature,
  metadata,
});

export const assertTimestampWithinTolerance = (
  timestampMs: number,
  receivedAt: Date,
  toleranceSeconds: number,
): void => {
  if (!Number.isFinite(timestampMs) || Math.abs(receivedAt.getTime() - timestampMs) > toleranceSeconds * 1_000) {
    throw new VerificationError('timestamp_skew', 'Webhook timestamp is outside the accepted tolerance');
  }
};

export const currentTime = (receivedAt: Date | undefined): Date => receivedAt ?? new Date();
