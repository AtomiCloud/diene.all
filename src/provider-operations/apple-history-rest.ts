import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { importPKCS8, SignJWT } from 'jose';
import type { Clock, SecretReader } from '../domain/index.ts';
import type { AppleHistoryFailure, AppleHistoryPage, AppleNotificationHistoryClient } from './apple-backfill.ts';
import { cancelResponseBody, type GooglePubSubFetch, readBoundedResponseBody } from './google-pubsub-rest.ts';

type AppleAppStoreServerEnvironment = 'Production' | 'Sandbox';

export interface AppleAppStoreServerTokenProvider {
  createToken(signal?: AbortSignal): Promise<Result<string, AppleHistoryFailure>>;
}

export interface AppleAppStoreJwtOptions {
  readonly issuerId: string;
  readonly keyId: string;
  readonly bundleId: string;
  readonly signingKeySecretRef: string;
  readonly tokenLifetimeSeconds?: number;
}

interface AppleNotificationHistoryRequest {
  readonly startDateMs: number;
  readonly endDateMs: number;
  readonly onlyFailures?: boolean;
  readonly transactionId?: string;
  readonly notificationType?: string;
  readonly subtype?: string;
}

export interface AppleNotificationHistoryRestOptions {
  readonly environment: AppleAppStoreServerEnvironment;
  readonly request: AppleNotificationHistoryRequest;
  readonly fetch?: GooglePubSubFetch;
  readonly timeoutMs?: number;
  readonly maxResponseBytes?: number;
}

interface NotificationHistoryResponseJson {
  readonly notificationHistory?: unknown;
  readonly hasMore?: unknown;
  readonly paginationToken?: unknown;
}

const PRODUCTION_BASE_URL = 'https://api.storekit.apple.com';
const SANDBOX_BASE_URL = 'https://api.storekit-sandbox.apple.com';
const DEFAULT_TIMEOUT_MS = 10_000;
const DEFAULT_MAX_RESPONSE_BYTES = 1_048_576;
const MAX_RESPONSE_BYTES = 4 * 1_048_576;
const APPLE_JWT_AUDIENCE = 'appstoreconnect-v1';
const DEFAULT_TOKEN_LIFETIME_SECONDS = 300;
const ISSUER_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/iu;
const KEY_ID = /^[A-Z0-9]{10}$/u;
const BUNDLE_ID = /^[A-Za-z0-9][A-Za-z0-9.-]{1,254}$/u;

const historyFailure = (code: string, message: string, retryable: boolean): AppleHistoryFailure => ({
  code,
  message,
  retryable,
});

const validateJwtOptions = (options: AppleAppStoreJwtOptions): void => {
  if (!ISSUER_ID.test(options.issuerId)) {
    throw new TypeError('Apple App Store issuer ID is invalid');
  }
  if (!KEY_ID.test(options.keyId)) {
    throw new TypeError('Apple App Store key ID is invalid');
  }
  if (!BUNDLE_ID.test(options.bundleId) || !options.bundleId.includes('.') || options.bundleId.includes('..')) {
    throw new TypeError('Apple App Store bundle ID is invalid');
  }
  if (options.signingKeySecretRef.length === 0) {
    throw new TypeError('Apple App Store signing-key secret reference is required');
  }
  const lifetime = options.tokenLifetimeSeconds ?? DEFAULT_TOKEN_LIFETIME_SECONDS;
  if (!Number.isSafeInteger(lifetime) || lifetime < 60 || lifetime > 3_600) {
    throw new RangeError('Apple App Store JWT lifetime must be between 60 and 3600 seconds');
  }
};

const validateHistoryOptions = (options: AppleNotificationHistoryRestOptions): void => {
  if (options.environment !== 'Production' && options.environment !== 'Sandbox') {
    throw new TypeError('Apple App Store environment is invalid');
  }
  const { startDateMs, endDateMs } = options.request;
  if (
    !Number.isSafeInteger(startDateMs) ||
    !Number.isSafeInteger(endDateMs) ||
    startDateMs < 0 ||
    endDateMs <= startDateMs
  ) {
    throw new RangeError('Apple notification-history dates must be ordered epoch milliseconds');
  }
  for (const value of [options.request.transactionId, options.request.notificationType, options.request.subtype]) {
    if (value !== undefined && (value.length === 0 || value.length > 256)) {
      throw new TypeError('Apple notification-history filter is invalid');
    }
  }
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 30_000) {
    throw new RangeError('Apple notification-history timeout must be between 1 and 30000 milliseconds');
  }
  const maxResponseBytes = options.maxResponseBytes ?? DEFAULT_MAX_RESPONSE_BYTES;
  if (!Number.isSafeInteger(maxResponseBytes) || maxResponseBytes < 1 || maxResponseBytes > MAX_RESPONSE_BYTES) {
    throw new RangeError('Apple notification-history response limit is invalid');
  }
};

class SecretBackedAppleAppStoreTokenProvider implements AppleAppStoreServerTokenProvider {
  readonly tokenLifetimeSeconds: number;

  constructor(
    readonly secrets: SecretReader,
    readonly clock: Clock,
    readonly options: AppleAppStoreJwtOptions,
  ) {
    validateJwtOptions(options);
    this.tokenLifetimeSeconds = options.tokenLifetimeSeconds ?? DEFAULT_TOKEN_LIFETIME_SECONDS;
  }

  async createToken(signal?: AbortSignal): Promise<Result<string, AppleHistoryFailure>> {
    const aborted = (): boolean => signal?.aborted === true;
    if (aborted()) {
      return Err(historyFailure('cancelled', 'Apple App Store authorization was cancelled', true));
    }
    const secretResult = await this.secrets.read(this.options.signingKeySecretRef);
    if (await secretResult.isErr()) {
      const secretFailure = await secretResult.unwrapErr();
      return Err(
        historyFailure(
          'authentication',
          `Apple App Store signing key is unavailable (${secretFailure.code})`,
          secretFailure.code === 'unavailable',
        ),
      );
    }
    if (aborted()) {
      return Err(historyFailure('cancelled', 'Apple App Store authorization was cancelled', true));
    }

    try {
      const pem = new TextDecoder('utf-8', { fatal: true }).decode(await secretResult.unwrap());
      const key = await importPKCS8(pem.trim(), 'ES256');
      const nowSeconds = Math.floor(this.clock.nowMs() / 1_000);
      const token = await new SignJWT({ bid: this.options.bundleId })
        .setProtectedHeader({
          alg: 'ES256',
          kid: this.options.keyId,
          typ: 'JWT',
        })
        .setIssuer(this.options.issuerId)
        .setAudience(APPLE_JWT_AUDIENCE)
        .setIssuedAt(nowSeconds)
        .setExpirationTime(nowSeconds + this.tokenLifetimeSeconds)
        .sign(key);
      return Ok(token);
    } catch {
      return Err(historyFailure('authentication', 'Apple App Store signing key is invalid', false));
    }
  }
}

const parseHistoryResponse = (input: unknown): Result<AppleHistoryPage, AppleHistoryFailure> => {
  if (input === null || typeof input !== 'object' || Array.isArray(input)) {
    return Err(historyFailure('protocol', 'Apple notification history returned an invalid response', false));
  }
  const value = input as NotificationHistoryResponseJson;
  if (
    !Array.isArray(value.notificationHistory) ||
    typeof value.hasMore !== 'boolean' ||
    typeof value.paginationToken !== 'string' ||
    value.paginationToken.length === 0 ||
    value.paginationToken.length > 8_192
  ) {
    return Err(historyFailure('protocol', 'Apple notification history returned an invalid response', false));
  }
  const notifications: Array<{ signedPayload: string }> = [];
  for (const item of value.notificationHistory) {
    const signedPayload =
      item !== null && typeof item === 'object' && !Array.isArray(item)
        ? (item as Record<string, unknown>).signedPayload
        : undefined;
    if (
      item === null ||
      typeof item !== 'object' ||
      Array.isArray(item) ||
      typeof signedPayload !== 'string' ||
      signedPayload.length === 0
    ) {
      return Err(historyFailure('protocol', 'Apple notification history returned an invalid response', false));
    }
    notifications.push({ signedPayload });
  }
  if (value.hasMore && notifications.length === 0) {
    return Err(historyFailure('protocol', 'Apple notification history returned an invalid response', false));
  }
  return Ok({
    notifications,
    hasMore: value.hasMore,
    cursorAfter: value.paginationToken,
  });
};

export class FetchAppleAppStoreNotificationHistoryClient implements AppleNotificationHistoryClient {
  readonly fetcher: GooglePubSubFetch;
  readonly baseUrl: string;
  readonly timeoutMs: number;
  readonly maxResponseBytes: number;

  constructor(
    readonly tokens: AppleAppStoreServerTokenProvider,
    readonly options: AppleNotificationHistoryRestOptions,
  ) {
    validateHistoryOptions(options);
    this.fetcher = options.fetch ?? fetch;
    this.baseUrl = options.environment === 'Production' ? PRODUCTION_BASE_URL : SANDBOX_BASE_URL;
    this.timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
    this.maxResponseBytes = options.maxResponseBytes ?? DEFAULT_MAX_RESPONSE_BYTES;
  }

  async listNotifications(input: {
    readonly cursor?: string;
    readonly limit: number;
    readonly signal: AbortSignal;
  }): Promise<Result<AppleHistoryPage, AppleHistoryFailure>> {
    if (
      !Number.isSafeInteger(input.limit) ||
      input.limit < 20 ||
      (input.cursor !== undefined && (input.cursor.length === 0 || input.cursor.length > 8_192))
    ) {
      return Err(historyFailure('protocol', 'Apple notification-history request is invalid', false));
    }
    if (input.signal.aborted) {
      return Err(historyFailure('cancelled', 'Apple notification-history request was cancelled', true));
    }

    const controller = new AbortController();
    let timedOut = false;
    const timeout = setTimeout(() => {
      timedOut = true;
      controller.abort();
    }, this.timeoutMs);
    const cancel = (): void => controller.abort();
    input.signal.addEventListener('abort', cancel, { once: true });
    const aborted = new Promise<null>(resolve => {
      controller.signal.addEventListener('abort', () => resolve(null), {
        once: true,
      });
    });

    try {
      const tokenAttempt = await Promise.race([
        this.tokens.createToken(controller.signal).then(result => ({ result })),
        aborted,
      ]);
      if (tokenAttempt === null) {
        return Err(this.abortFailure(input.signal, timedOut));
      }
      if (await tokenAttempt.result.isErr()) {
        const tokenFailure = await tokenAttempt.result.unwrapErr();
        return Err(
          historyFailure(
            tokenFailure.code,
            `Apple App Store authorization failed (${tokenFailure.code})`,
            tokenFailure.retryable,
          ),
        );
      }
      const token = await tokenAttempt.result.unwrap();
      const url = new URL('/inApps/v1/notifications/history', this.baseUrl);
      if (input.cursor !== undefined) {
        url.searchParams.set('paginationToken', input.cursor);
      }
      let response: Response;
      try {
        response = await this.fetcher(url, {
          method: 'POST',
          headers: {
            Accept: 'application/json',
            Authorization: `Bearer ${token}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(this.requestBody()),
          cache: 'no-store',
          credentials: 'omit',
          redirect: 'error',
          referrerPolicy: 'no-referrer',
          signal: controller.signal,
        });
      } catch {
        return Err(
          controller.signal.aborted
            ? this.abortFailure(input.signal, timedOut)
            : historyFailure('network', 'Apple notification-history request could not connect', true),
        );
      }

      if (controller.signal.aborted) {
        cancelResponseBody(response);
        return Err(this.abortFailure(input.signal, timedOut));
      }
      if (!response.ok) {
        cancelResponseBody(response);
        return Err(
          historyFailure(
            'http',
            `Apple notification-history request failed with HTTP ${response.status}`,
            response.status === 408 || response.status === 429 || response.status >= 500,
          ),
        );
      }
      const bodyResult = await readBoundedResponseBody(response, this.maxResponseBytes, controller.signal);
      if (!bodyResult.ok) {
        if (bodyResult.failure === 'too-large') {
          return Err(historyFailure('protocol', 'Apple notification-history response exceeded the size limit', false));
        }
        return Err(
          bodyResult.failure === 'cancelled'
            ? this.abortFailure(input.signal, timedOut)
            : historyFailure('network', 'Apple notification-history response could not be read', true),
        );
      }
      let payload: unknown;
      try {
        payload = JSON.parse(new TextDecoder().decode(bodyResult.bytes)) as unknown;
      } catch {
        return Err(historyFailure('protocol', 'Apple notification history returned invalid JSON', false));
      }
      return parseHistoryResponse(payload);
    } finally {
      clearTimeout(timeout);
      input.signal.removeEventListener('abort', cancel);
    }
  }

  private abortFailure(signal: AbortSignal, timedOut: boolean): AppleHistoryFailure {
    return timedOut
      ? historyFailure('timeout', 'Apple notification-history request timed out', true)
      : historyFailure(
          'cancelled',
          signal.aborted
            ? 'Apple notification-history request was cancelled'
            : 'Apple notification-history authorization was cancelled',
          true,
        );
  }

  private requestBody(): Record<string, unknown> {
    return {
      startDate: this.options.request.startDateMs,
      endDate: this.options.request.endDateMs,
      ...(this.options.request.onlyFailures === undefined ? {} : { onlyFailures: this.options.request.onlyFailures }),
      ...(this.options.request.transactionId === undefined
        ? {}
        : { transactionId: this.options.request.transactionId }),
      ...(this.options.request.notificationType === undefined
        ? {}
        : { notificationType: this.options.request.notificationType }),
      ...(this.options.request.subtype === undefined ? {} : { subtype: this.options.request.subtype }),
    };
  }
}

export const createAppleAppStoreNotificationHistoryClient = (
  secrets: SecretReader,
  clock: Clock,
  jwt: AppleAppStoreJwtOptions,
  options: AppleNotificationHistoryRestOptions,
): AppleNotificationHistoryClient =>
  new FetchAppleAppStoreNotificationHistoryClient(
    new SecretBackedAppleAppStoreTokenProvider(secrets, clock, jwt),
    options,
  );
