import {
  assertSecrets,
  assertTimestampWithinTolerance,
  constantTimeHexEqual,
  currentTime,
  decodeBody,
  hmacSha256,
  numberField,
  parseJson,
  requireHeader,
  stringField,
  verifiedWebhook,
} from './shared.ts';
import type { ProviderVerifier, VerificationRequest, VerifiedWebhook } from './types.ts';
import { VerificationError } from './types.ts';

export interface StripeConfiguration {
  readonly secrets: readonly string[];
  readonly toleranceSeconds?: number;
}

const parseSignatureHeader = (value: string): { timestamp: number; signatures: readonly string[] } => {
  let timestamp: number | undefined;
  const signatures: string[] = [];

  for (const component of value.split(',')) {
    const separator = component.indexOf('=');
    if (separator < 1) {
      continue;
    }
    const key = component.slice(0, separator).trim();
    const componentValue = component.slice(separator + 1).trim();
    if (key === 't' && /^\d+$/.test(componentValue)) {
      timestamp = Number(componentValue);
    } else if (key === 'v1' && componentValue.length > 0) {
      signatures.push(componentValue);
    }
  }

  if (timestamp === undefined || !Number.isSafeInteger(timestamp) || signatures.length === 0) {
    throw new VerificationError('malformed_header', 'Stripe-Signature header is malformed');
  }

  return { timestamp, signatures };
};

const verifyStripe = async (
  request: VerificationRequest,
  configuration: StripeConfiguration,
): Promise<VerifiedWebhook> => {
  assertSecrets(configuration.secrets);
  const signatureHeader = requireHeader(request.headers, 'Stripe-Signature');
  const { timestamp, signatures } = parseSignatureHeader(signatureHeader);
  const toleranceSeconds = configuration.toleranceSeconds ?? 300;

  if (toleranceSeconds < 0 || !Number.isFinite(toleranceSeconds)) {
    throw new VerificationError('invalid_configuration', 'Stripe timestamp tolerance must be non-negative');
  }

  const body = decodeBody(request.rawBody);
  const valid = configuration.secrets.some(secret => {
    const expected = hmacSha256(secret, [`${timestamp}.`, body]);
    return signatures.some(signature => constantTimeHexEqual(expected, signature));
  });

  if (!valid) {
    throw new VerificationError('invalid_signature', 'Stripe signature is invalid');
  }

  assertTimestampWithinTolerance(timestamp * 1_000, currentTime(request.receivedAt), toleranceSeconds);

  const payload = parseJson(request.rawBody);
  const eventId = stringField(payload, 'id');
  const eventType = stringField(payload, 'type');
  const created = numberField(payload, 'created');

  return verifiedWebhook('stripe', request.rawBody, signatureHeader, {
    eventId,
    eventType,
    providerTimestamp: created === undefined ? timestamp * 1_000 : created * 1_000,
  });
};

export const stripeVerifier: ProviderVerifier<StripeConfiguration> = {
  provider: 'stripe',
  verify: verifyStripe,
};
