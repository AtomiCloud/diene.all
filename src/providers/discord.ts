import { verifyAsync } from '@noble/ed25519';
import {
  assertTimestampWithinTolerance,
  currentTime,
  parseJson,
  requireHeader,
  stringField,
  verifiedWebhook,
} from './shared.ts';
import type { ProviderVerifier, VerificationRequest, VerifiedWebhook } from './types.ts';
import { VerificationError } from './types.ts';

export interface DiscordConfiguration {
  readonly publicKeys: readonly string[];
  readonly toleranceSeconds?: number;
}

const decodeHex = (value: string, expectedBytes: number, label: string): Uint8Array => {
  if (value.length !== expectedBytes * 2 || !/^[\da-f]+$/i.test(value)) {
    throw new VerificationError('malformed_header', `Discord ${label} is malformed`);
  }
  return Buffer.from(value, 'hex');
};

const signedMessage = (timestamp: string, rawBody: Uint8Array): Uint8Array => {
  const timestampBytes = new TextEncoder().encode(timestamp);
  const message = new Uint8Array(timestampBytes.length + rawBody.length);
  message.set(timestampBytes);
  message.set(rawBody, timestampBytes.length);
  return message;
};

const verifyDiscord = async (
  request: VerificationRequest,
  configuration: DiscordConfiguration,
): Promise<VerifiedWebhook> => {
  if (configuration.publicKeys.length === 0) {
    throw new VerificationError('invalid_configuration', 'At least one Discord public key is required');
  }

  const signatureHeader = requireHeader(request.headers, 'X-Signature-Ed25519');
  const timestampHeader = requireHeader(request.headers, 'X-Signature-Timestamp');
  const signature = decodeHex(signatureHeader, 64, 'signature');
  const timestampSeconds = Number(timestampHeader);
  if (!/^\d+$/.test(timestampHeader) || !Number.isSafeInteger(timestampSeconds)) {
    throw new VerificationError('malformed_header', 'Discord timestamp is malformed');
  }

  const message = signedMessage(timestampHeader, request.rawBody);
  let valid = false;
  for (const publicKeyValue of configuration.publicKeys) {
    const publicKey = decodeHex(publicKeyValue, 32, 'public key');
    try {
      valid = (await verifyAsync(signature, message, publicKey, { zip215: false })) || valid;
    } catch {
      // Try every dual-live key before returning the provider-safe error.
    }
  }
  if (!valid) {
    throw new VerificationError('invalid_signature', 'Discord signature is invalid');
  }

  if (configuration.toleranceSeconds !== undefined) {
    if (configuration.toleranceSeconds < 0 || !Number.isFinite(configuration.toleranceSeconds)) {
      throw new VerificationError('invalid_configuration', 'Discord timestamp tolerance must be non-negative');
    }
    assertTimestampWithinTolerance(
      timestampSeconds * 1_000,
      currentTime(request.receivedAt),
      configuration.toleranceSeconds,
    );
  }

  const payload = parseJson(request.rawBody);
  return verifiedWebhook('discord', request.rawBody, signatureHeader, {
    eventId: stringField(payload, 'id'),
    providerTimestamp: timestampSeconds * 1_000,
  });
};

export const discordVerifier: ProviderVerifier<DiscordConfiguration> = {
  provider: 'discord',
  verify: verifyDiscord,
};
