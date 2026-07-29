import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { importPKCS8, SignJWT } from 'jose';
import type { Clock, SecretReader } from '../domain/index.ts';
import {
  cancelResponseBody,
  type GoogleOAuthAccessTokenReader,
  type GoogleOAuthTokenFailure,
  type GooglePubSubFetch,
  readBoundedResponseBody,
} from './google-pubsub-rest.ts';

export const GOOGLE_PUBSUB_OAUTH_SCOPE = 'https://www.googleapis.com/auth/pubsub';
export const GOOGLE_CLOUD_PLATFORM_OAUTH_SCOPE = 'https://www.googleapis.com/auth/cloud-platform';

export type GooglePubSubOAuthScope = typeof GOOGLE_PUBSUB_OAUTH_SCOPE | typeof GOOGLE_CLOUD_PLATFORM_OAUTH_SCOPE;

interface GoogleServiceAccountCredential {
  readonly privateKeyId: string;
  readonly privateKeyPem: string;
  readonly clientEmail: string;
  readonly tokenUri: string;
}

export interface GoogleServiceAccountAssertionSigner {
  signAssertion(input: {
    readonly credential: GoogleServiceAccountCredential;
    readonly scopes: readonly GooglePubSubOAuthScope[];
    readonly issuedAtSeconds: number;
    readonly expiresAtSeconds: number;
    readonly signal?: AbortSignal;
  }): Promise<Result<string, GoogleOAuthTokenFailure>>;
}

export interface GoogleServiceAccountOAuthOptions {
  readonly credentialSecretRef: string;
  readonly expectedServiceAccountEmail: string;
  readonly scopes?: readonly GooglePubSubOAuthScope[];
  readonly fetch?: GooglePubSubFetch;
  readonly timeoutMs?: number;
  readonly maxResponseBytes?: number;
  readonly cacheSkewMs?: number;
  readonly assertionLifetimeSeconds?: number;
}

interface ServiceAccountJson {
  readonly type?: unknown;
  readonly private_key_id?: unknown;
  readonly private_key?: unknown;
  readonly client_email?: unknown;
  readonly token_uri?: unknown;
}

interface TokenResponseJson {
  readonly access_token?: unknown;
  readonly token_type?: unknown;
  readonly expires_in?: unknown;
  readonly scope?: unknown;
}

const DEFAULT_TIMEOUT_MS = 10_000;
const DEFAULT_MAX_RESPONSE_BYTES = 1_048_576;
const MAX_RESPONSE_BYTES = 4 * 1_048_576;
const DEFAULT_CACHE_SKEW_MS = 60_000;
const DEFAULT_ASSERTION_LIFETIME_SECONDS = 3_600;
const JWT_BEARER_GRANT_TYPE = 'urn:ietf:params:oauth:grant-type:jwt-bearer';
const ALLOWED_TOKEN_URIS = new Set([
  'https://oauth2.googleapis.com/token',
  'https://accounts.google.com/o/oauth2/token',
]);
const SERVICE_ACCOUNT_EMAIL = /^[A-Za-z0-9][A-Za-z0-9._-]{0,126}@[A-Za-z0-9.-]+\.gserviceaccount\.com$/u;

const oauthFailure = (code: string, message: string, retryable: boolean): GoogleOAuthTokenFailure => ({
  code,
  message,
  retryable,
});

const configuredScopes = (options: GoogleServiceAccountOAuthOptions): readonly GooglePubSubOAuthScope[] => {
  const scopes = options.scopes ?? [GOOGLE_PUBSUB_OAUTH_SCOPE];
  const allowed = new Set<GooglePubSubOAuthScope>([GOOGLE_PUBSUB_OAUTH_SCOPE, GOOGLE_CLOUD_PLATFORM_OAUTH_SCOPE]);
  if (scopes.length === 0 || new Set(scopes).size !== scopes.length || scopes.some(scope => !allowed.has(scope))) {
    throw new TypeError('Google OAuth scopes must be the approved Pub/Sub scope set');
  }
  return [...scopes];
};

const validateOptions = (options: GoogleServiceAccountOAuthOptions): void => {
  if (options.credentialSecretRef.length === 0) {
    throw new TypeError('Google service-account credential secret reference is required');
  }
  if (!SERVICE_ACCOUNT_EMAIL.test(options.expectedServiceAccountEmail)) {
    throw new TypeError('Google service-account email is invalid');
  }
  configuredScopes(options);
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 30_000) {
    throw new RangeError('Google OAuth timeout must be between 1 and 30000 milliseconds');
  }
  const maxResponseBytes = options.maxResponseBytes ?? DEFAULT_MAX_RESPONSE_BYTES;
  if (!Number.isSafeInteger(maxResponseBytes) || maxResponseBytes < 1 || maxResponseBytes > MAX_RESPONSE_BYTES) {
    throw new RangeError('Google OAuth response limit is invalid');
  }
  const cacheSkewMs = options.cacheSkewMs ?? DEFAULT_CACHE_SKEW_MS;
  if (!Number.isSafeInteger(cacheSkewMs) || cacheSkewMs < 0 || cacheSkewMs > 600_000) {
    throw new RangeError('Google OAuth cache skew must be between 0 and 600000 milliseconds');
  }
  const assertionLifetimeSeconds = options.assertionLifetimeSeconds ?? DEFAULT_ASSERTION_LIFETIME_SECONDS;
  if (
    !Number.isSafeInteger(assertionLifetimeSeconds) ||
    assertionLifetimeSeconds < 60 ||
    assertionLifetimeSeconds > 3_600
  ) {
    throw new RangeError('Google OAuth assertion lifetime must be between 60 and 3600 seconds');
  }
};

const parseCredential = (
  bytes: Uint8Array,
  expectedServiceAccountEmail: string,
): Result<GoogleServiceAccountCredential, GoogleOAuthTokenFailure> => {
  let input: unknown;
  try {
    input = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)) as unknown;
  } catch {
    return Err(oauthFailure('credential', 'Google service-account credential is malformed', false));
  }
  if (input === null || typeof input !== 'object' || Array.isArray(input)) {
    return Err(oauthFailure('credential', 'Google service-account credential is malformed', false));
  }
  const value = input as ServiceAccountJson;
  if (
    value.type !== 'service_account' ||
    typeof value.private_key_id !== 'string' ||
    value.private_key_id.length === 0 ||
    value.private_key_id.length > 256 ||
    !/^[A-Za-z0-9_-]+$/u.test(value.private_key_id) ||
    typeof value.private_key !== 'string' ||
    !value.private_key.includes('BEGIN PRIVATE KEY') ||
    typeof value.client_email !== 'string' ||
    value.client_email !== expectedServiceAccountEmail ||
    typeof value.token_uri !== 'string' ||
    !ALLOWED_TOKEN_URIS.has(value.token_uri)
  ) {
    return Err(oauthFailure('credential', 'Google service-account credential does not match configuration', false));
  }
  return Ok({
    privateKeyId: value.private_key_id,
    privateKeyPem: value.private_key,
    clientEmail: value.client_email,
    tokenUri: value.token_uri,
  });
};

class JoseGoogleServiceAccountAssertionSigner implements GoogleServiceAccountAssertionSigner {
  async signAssertion(input: {
    readonly credential: GoogleServiceAccountCredential;
    readonly scopes: readonly GooglePubSubOAuthScope[];
    readonly issuedAtSeconds: number;
    readonly expiresAtSeconds: number;
    readonly signal?: AbortSignal;
  }): Promise<Result<string, GoogleOAuthTokenFailure>> {
    const aborted = (): boolean => input.signal?.aborted === true;
    if (aborted()) {
      return Err(oauthFailure('cancelled', 'Google OAuth signing was cancelled', true));
    }
    try {
      const key = await importPKCS8(input.credential.privateKeyPem.trim(), 'RS256');
      if (aborted()) {
        return Err(oauthFailure('cancelled', 'Google OAuth signing was cancelled', true));
      }
      const assertion = await new SignJWT({
        scope: input.scopes.join(' '),
      })
        .setProtectedHeader({
          alg: 'RS256',
          typ: 'JWT',
          kid: input.credential.privateKeyId,
        })
        .setIssuer(input.credential.clientEmail)
        .setAudience(input.credential.tokenUri)
        .setIssuedAt(input.issuedAtSeconds)
        .setExpirationTime(input.expiresAtSeconds)
        .sign(key);
      return Ok(assertion);
    } catch {
      return Err(oauthFailure('credential', 'Google service-account private key is invalid', false));
    }
  }
}

export class SecretBackedGoogleOAuthAccessTokenReader implements GoogleOAuthAccessTokenReader {
  readonly fetcher: GooglePubSubFetch;
  readonly scopes: readonly GooglePubSubOAuthScope[];
  readonly timeoutMs: number;
  readonly maxResponseBytes: number;
  readonly cacheSkewMs: number;
  readonly assertionLifetimeSeconds: number;
  private cached: { readonly accessToken: string; readonly expiresAtMs: number } | undefined;

  constructor(
    readonly secrets: SecretReader,
    readonly clock: Clock,
    readonly options: GoogleServiceAccountOAuthOptions,
    readonly signer: GoogleServiceAccountAssertionSigner = new JoseGoogleServiceAccountAssertionSigner(),
  ) {
    validateOptions(options);
    this.fetcher = options.fetch ?? fetch;
    this.scopes = configuredScopes(options);
    this.timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
    this.maxResponseBytes = options.maxResponseBytes ?? DEFAULT_MAX_RESPONSE_BYTES;
    this.cacheSkewMs = options.cacheSkewMs ?? DEFAULT_CACHE_SKEW_MS;
    this.assertionLifetimeSeconds = options.assertionLifetimeSeconds ?? DEFAULT_ASSERTION_LIFETIME_SECONDS;
  }

  async readAccessToken(signal?: AbortSignal): Promise<Result<string, GoogleOAuthTokenFailure>> {
    if (signal?.aborted === true) {
      return Err(oauthFailure('cancelled', 'Google OAuth request was cancelled', true));
    }
    const nowMs = this.clock.nowMs();
    if (this.cached !== undefined && nowMs + this.cacheSkewMs < this.cached.expiresAtMs) {
      return Ok(this.cached.accessToken);
    }
    const controller = new AbortController();
    let timedOut = false;
    const timeout = setTimeout(() => {
      timedOut = true;
      controller.abort();
    }, this.timeoutMs);
    const cancel = (): void => controller.abort();
    signal?.addEventListener('abort', cancel, { once: true });
    const aborted = new Promise<null>(resolve => {
      controller.signal.addEventListener('abort', () => resolve(null), {
        once: true,
      });
    });

    try {
      const credentialAttempt = await Promise.race([
        this.secrets.read(this.options.credentialSecretRef).then(result => ({ result })),
        aborted,
      ]);
      if (credentialAttempt === null) {
        return Err(this.abortFailure(signal, timedOut));
      }
      if (await credentialAttempt.result.isErr()) {
        const secretFailure = await credentialAttempt.result.unwrapErr();
        return Err(
          oauthFailure(
            'credential',
            `Google service-account credential is unavailable (${secretFailure.code})`,
            secretFailure.code === 'unavailable',
          ),
        );
      }
      const credentialResult = parseCredential(
        await credentialAttempt.result.unwrap(),
        this.options.expectedServiceAccountEmail,
      );
      if (await credentialResult.isErr()) {
        return Err(await credentialResult.unwrapErr());
      }
      const credential = await credentialResult.unwrap();
      const issuedAtSeconds = Math.floor(nowMs / 1_000);
      const assertionAttempt = await Promise.race([
        this.signer
          .signAssertion({
            credential,
            scopes: this.scopes,
            issuedAtSeconds,
            expiresAtSeconds: issuedAtSeconds + this.assertionLifetimeSeconds,
            signal: controller.signal,
          })
          .then(result => ({ result })),
        aborted,
      ]);
      if (assertionAttempt === null) {
        return Err(this.abortFailure(signal, timedOut));
      }
      if (await assertionAttempt.result.isErr()) {
        const signingFailure = await assertionAttempt.result.unwrapErr();
        return Err(
          oauthFailure(
            signingFailure.code,
            `Google OAuth assertion signing failed (${signingFailure.code})`,
            signingFailure.retryable,
          ),
        );
      }
      const assertion = await assertionAttempt.result.unwrap();
      const form = new URLSearchParams({
        grant_type: JWT_BEARER_GRANT_TYPE,
        assertion,
      });
      let response: Response;
      try {
        response = await this.fetcher(credential.tokenUri, {
          method: 'POST',
          headers: {
            Accept: 'application/json',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: form.toString(),
          cache: 'no-store',
          credentials: 'omit',
          redirect: 'error',
          referrerPolicy: 'no-referrer',
          signal: controller.signal,
        });
      } catch {
        return Err(
          controller.signal.aborted
            ? this.abortFailure(signal, timedOut)
            : oauthFailure('network', 'Google OAuth token request could not connect', true),
        );
      }
      if (controller.signal.aborted) {
        cancelResponseBody(response);
        return Err(this.abortFailure(signal, timedOut));
      }
      if (!response.ok) {
        cancelResponseBody(response);
        return Err(
          oauthFailure(
            'http',
            `Google OAuth token request failed with HTTP ${response.status}`,
            response.status === 408 || response.status === 429 || response.status >= 500,
          ),
        );
      }
      const bodyResult = await readBoundedResponseBody(response, this.maxResponseBytes, controller.signal);
      if (!bodyResult.ok) {
        if (bodyResult.failure === 'too-large') {
          return Err(oauthFailure('protocol', 'Google OAuth token response exceeded the size limit', false));
        }
        return Err(
          bodyResult.failure === 'cancelled'
            ? this.abortFailure(signal, timedOut)
            : oauthFailure('network', 'Google OAuth token response could not be read', true),
        );
      }
      let payload: unknown;
      try {
        payload = JSON.parse(new TextDecoder().decode(bodyResult.bytes)) as unknown;
      } catch {
        return Err(oauthFailure('protocol', 'Google OAuth token response was invalid JSON', false));
      }
      const parsed = this.parseTokenResponse(payload);
      if (await parsed.isErr()) {
        return Err(await parsed.unwrapErr());
      }
      const value = await parsed.unwrap();
      this.cached = {
        accessToken: value.accessToken,
        expiresAtMs: nowMs + value.expiresInSeconds * 1_000,
      };
      return Ok(value.accessToken);
    } finally {
      clearTimeout(timeout);
      signal?.removeEventListener('abort', cancel);
    }
  }

  private abortFailure(signal: AbortSignal | undefined, timedOut: boolean): GoogleOAuthTokenFailure {
    return timedOut
      ? oauthFailure('timeout', 'Google OAuth token request timed out', true)
      : oauthFailure(
          'cancelled',
          signal?.aborted === true
            ? 'Google OAuth token request was cancelled'
            : 'Google OAuth token signing was cancelled',
          true,
        );
  }

  private parseTokenResponse(
    input: unknown,
  ): Result<{ readonly accessToken: string; readonly expiresInSeconds: number }, GoogleOAuthTokenFailure> {
    if (input === null || typeof input !== 'object' || Array.isArray(input)) {
      return Err(oauthFailure('protocol', 'Google OAuth token response was malformed', false));
    }
    const value = input as TokenResponseJson;
    if (
      typeof value.access_token !== 'string' ||
      value.access_token.length === 0 ||
      value.access_token.length > 16_384 ||
      value.token_type !== 'Bearer' ||
      typeof value.expires_in !== 'number' ||
      !Number.isSafeInteger(value.expires_in) ||
      value.expires_in < 1 ||
      value.expires_in > 86_400
    ) {
      return Err(oauthFailure('protocol', 'Google OAuth token response was malformed', false));
    }
    if (value.scope !== undefined) {
      if (typeof value.scope !== 'string') {
        return Err(oauthFailure('protocol', 'Google OAuth token response scope was invalid', false));
      }
      const granted = new Set(value.scope.split(/\s+/u).filter(Boolean));
      if (this.scopes.some(scope => !granted.has(scope))) {
        return Err(oauthFailure('protocol', 'Google OAuth token response omitted a required scope', false));
      }
    }
    return Ok({
      accessToken: value.access_token,
      expiresInSeconds: value.expires_in,
    });
  }
}

export const createGoogleServiceAccountOAuthAccessTokenReader = (
  secrets: SecretReader,
  clock: Clock,
  options: GoogleServiceAccountOAuthOptions,
  signer?: GoogleServiceAccountAssertionSigner,
): GoogleOAuthAccessTokenReader => new SecretBackedGoogleOAuthAccessTokenReader(secrets, clock, options, signer);
