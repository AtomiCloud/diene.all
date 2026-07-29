import {
  assertSecrets,
  constantTimeStringEqual,
  numberField,
  parseJson,
  requireHeader,
  verifiedWebhook,
} from './shared.ts';
import type { ProviderVerifier, VerificationRequest, VerifiedWebhook } from './types.ts';
import { VerificationError } from './types.ts';

export interface TelegramConfiguration {
  readonly secrets: readonly string[];
}

const verifyTelegram = async (
  request: VerificationRequest,
  configuration: TelegramConfiguration,
): Promise<VerifiedWebhook> => {
  assertSecrets(configuration.secrets);
  const submittedToken = requireHeader(request.headers, 'X-Telegram-Bot-Api-Secret-Token');
  const valid = configuration.secrets.some(secret => constantTimeStringEqual(secret, submittedToken));
  if (!valid) {
    throw new VerificationError('invalid_signature', 'Telegram secret token is invalid');
  }

  const payload = parseJson(request.rawBody);
  const updateId = numberField(payload, 'update_id');

  return verifiedWebhook('telegram', request.rawBody, submittedToken, {
    eventId: updateId !== undefined && Number.isSafeInteger(updateId) ? String(updateId) : undefined,
    sequence: updateId !== undefined && Number.isSafeInteger(updateId) ? String(updateId) : undefined,
  });
};

export const telegramVerifier: ProviderVerifier<TelegramConfiguration> = {
  provider: 'telegram',
  verify: verifyTelegram,
};
