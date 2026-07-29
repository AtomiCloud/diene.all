import { type RawBodyHmacConfiguration, verifyRawBodyHmac } from './hmac.ts';
import { parseJson, parseTimestamp, stringField } from './shared.ts';
import type { ProviderVerifier, VerificationRequest, VerifiedWebhook } from './types.ts';

export type LogtoConfiguration = RawBodyHmacConfiguration;

const verifyLogto = async (
  request: VerificationRequest,
  configuration: LogtoConfiguration,
): Promise<VerifiedWebhook> => {
  /*
   * Authenticate the raw bytes before parsing provider-controlled JSON.
   * Logto does not expose a delivery event ID, so the shared verifier derives
   * the payload+signature fallback.
   */
  return parseJsonAfterVerification(request, configuration);
};

const parseJsonAfterVerification = (
  request: VerificationRequest,
  configuration: LogtoConfiguration,
): VerifiedWebhook => {
  const signatureHeader = 'logto-signature-sha-256';
  const authenticated = verifyRawBodyHmac('logto', request, configuration, signatureHeader, {});
  const payload = parseJson(request.rawBody);
  return {
    ...authenticated,
    metadata: {
      eventType: stringField(payload, 'event'),
      providerTimestamp: parseTimestamp(stringField(payload, 'createdAt')),
    },
  };
};

export const logtoVerifier: ProviderVerifier<LogtoConfiguration> = {
  provider: 'logto',
  verify: verifyLogto,
};
