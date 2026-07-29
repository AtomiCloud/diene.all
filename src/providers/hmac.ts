import { assertSecrets, constantTimeHexEqual, hmacSha256, requireHeader, verifiedWebhook } from './shared.ts';
import type { ProviderMetadata, ProviderName, VerificationRequest, VerifiedWebhook } from './types.ts';
import { VerificationError } from './types.ts';

export interface RawBodyHmacConfiguration {
  readonly secrets: readonly string[];
}

export const verifyRawBodyHmac = (
  provider: ProviderName,
  request: VerificationRequest,
  configuration: RawBodyHmacConfiguration,
  signatureHeader: string,
  metadata: ProviderMetadata,
): VerifiedWebhook => {
  assertSecrets(configuration.secrets);
  const submittedSignature = requireHeader(request.headers, signatureHeader);
  const valid = configuration.secrets.some(secret =>
    constantTimeHexEqual(hmacSha256(secret, [request.rawBody]), submittedSignature),
  );

  if (!valid) {
    throw new VerificationError('invalid_signature', `${provider} signature is invalid`);
  }

  return verifiedWebhook(provider, request.rawBody, submittedSignature.toLowerCase(), metadata);
};
