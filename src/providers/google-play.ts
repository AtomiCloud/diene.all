import type { KeyObject } from 'node:crypto';
import { type JWK, type JWTPayload, type JWTVerifyGetKey, type JWTVerifyOptions, jwtVerify } from 'jose';
import {
  constantTimeStringEqual,
  parseJson,
  parseTimestamp,
  requireHeader,
  stringField,
  verifiedWebhook,
} from './shared.ts';
import type { ProviderVerifier, VerificationRequest, VerifiedWebhook } from './types.ts';
import { VerificationDependencyError, VerificationError } from './types.ts';

type GoogleJwtKey = CryptoKey | KeyObject | JWK | Uint8Array | JWTVerifyGetKey;

export interface GooglePlayConfiguration {
  readonly key: GoogleJwtKey;
  readonly serviceAccountEmail: string;
  /**
   * Pub/Sub defaults the OIDC audience to the push endpoint URL. Omitting this
   * value deliberately selects the stored registered URL from the route.
   */
  readonly audience?: string;
}

const verifyJwt = async (
  token: string,
  key: GoogleJwtKey,
  audience: string,
  currentDate: Date,
): Promise<JWTPayload> => {
  const options: JWTVerifyOptions = {
    algorithms: ['RS256'],
    audience,
    currentDate,
    issuer: ['https://accounts.google.com', 'accounts.google.com'],
  };

  if (isKeyResolver(key)) {
    const guardedKeyResolver: JWTVerifyGetKey = async (...arguments_) => {
      try {
        return await key(...arguments_);
      } catch (error) {
        if (error instanceof VerificationDependencyError) {
          throw error;
        }
        throw new VerificationDependencyError(
          'key_resolution_failed',
          'Google Pub/Sub OIDC verification key is unavailable',
          { cause: error },
        );
      }
    };
    return (await jwtVerify(token, guardedKeyResolver, options)).payload;
  }
  return (await jwtVerify(token, key, options)).payload;
};

const isKeyResolver = (key: GoogleJwtKey): key is JWTVerifyGetKey => typeof key === 'function';

const verifyGooglePlay = async (
  request: VerificationRequest,
  configuration: GooglePlayConfiguration,
): Promise<VerifiedWebhook> => {
  if (configuration.serviceAccountEmail.length === 0) {
    throw new VerificationError('invalid_configuration', 'Google Pub/Sub service account email is required');
  }

  const authorization = requireHeader(request.headers, 'Authorization');
  const match = /^Bearer ([^\s]+)$/i.exec(authorization);
  if (match?.[1] === undefined) {
    throw new VerificationError('malformed_header', 'Google Pub/Sub Authorization header is malformed');
  }

  let claims: JWTPayload;
  try {
    claims = await verifyJwt(
      match[1],
      configuration.key,
      configuration.audience ?? request.registeredUrl,
      request.receivedAt ?? new Date(),
    );
  } catch (error) {
    if (error instanceof VerificationDependencyError) {
      throw error;
    }
    throw new VerificationError('invalid_signature', 'Google Pub/Sub OIDC token is invalid', { cause: error });
  }

  if (
    typeof claims.email !== 'string' ||
    !constantTimeStringEqual(configuration.serviceAccountEmail, claims.email) ||
    (claims.email_verified !== true && claims.email_verified !== 'true')
  ) {
    throw new VerificationError('invalid_claims', 'Google Pub/Sub OIDC identity does not match the subscription');
  }

  const payload = parseJson(request.rawBody);
  const message = payload.message;
  if (message === null || typeof message !== 'object' || Array.isArray(message)) {
    throw new VerificationError('malformed_payload', 'Google Pub/Sub message is missing');
  }
  const messageRecord = message as Record<string, unknown>;

  return verifiedWebhook('google-play', request.rawBody, match[1], {
    eventId: stringField(messageRecord, 'messageId') ?? stringField(messageRecord, 'message_id'),
    providerTimestamp: parseTimestamp(
      stringField(messageRecord, 'publishTime') ?? stringField(messageRecord, 'publish_time'),
    ),
  });
};

export const googlePlayVerifier: ProviderVerifier<GooglePlayConfiguration> = {
  provider: 'google-play',
  verify: verifyGooglePlay,
};
