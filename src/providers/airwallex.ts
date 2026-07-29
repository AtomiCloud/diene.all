import {
  assertSecrets,
  assertTimestampWithinTolerance,
  constantTimeHexEqual,
  currentTime,
  decodeBody,
  hmacSha256,
  parseJson,
  parseTimestamp,
  requireHeader,
  stringField,
  verifiedWebhook,
} from './shared.ts';
import type { ProviderVerifier, VerificationRequest, VerifiedWebhook } from './types.ts';
import { VerificationError } from './types.ts';

export interface AirwallexConfiguration {
  readonly secrets: readonly string[];
  readonly toleranceSeconds?: number;
}

const verifyAirwallex = async (
  request: VerificationRequest,
  configuration: AirwallexConfiguration,
): Promise<VerifiedWebhook> => {
  assertSecrets(configuration.secrets);
  const timestampHeader = requireHeader(request.headers, 'x-timestamp');
  const signature = requireHeader(request.headers, 'x-signature');
  const timestamp = Number(timestampHeader);
  const toleranceSeconds = configuration.toleranceSeconds ?? 300;

  if (!/^\d+$/.test(timestampHeader) || !Number.isSafeInteger(timestamp)) {
    throw new VerificationError('malformed_header', 'Airwallex timestamp is malformed');
  }
  if (toleranceSeconds < 0 || !Number.isFinite(toleranceSeconds)) {
    throw new VerificationError('invalid_configuration', 'Airwallex timestamp tolerance must be non-negative');
  }

  const body = decodeBody(request.rawBody);
  const valid = configuration.secrets.some(secret =>
    constantTimeHexEqual(hmacSha256(secret, [timestampHeader, body]), signature),
  );
  if (!valid) {
    throw new VerificationError('invalid_signature', 'Airwallex signature is invalid');
  }

  assertTimestampWithinTolerance(timestamp, currentTime(request.receivedAt), toleranceSeconds);

  const payload = parseJson(request.rawBody);
  return verifiedWebhook('airwallex', request.rawBody, signature, {
    eventId: stringField(payload, 'id'),
    eventType: stringField(payload, 'name'),
    providerTimestamp: parseTimestamp(stringField(payload, 'created_at')) ?? timestamp,
  });
};

export const airwallexVerifier: ProviderVerifier<AirwallexConfiguration> = {
  provider: 'airwallex',
  verify: verifyAirwallex,
};
