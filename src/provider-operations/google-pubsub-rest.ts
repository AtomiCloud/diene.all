import { Err, Ok, type Result } from '@atomicloud/diene.result';
import type {
  GooglePubSubAdminFailure,
  GooglePubSubAdministrationClient,
  GooglePubSubDesiredState,
  GooglePubSubSubscriptionState,
  GooglePubSubUpdateField,
} from './google-rtdn-reconciler.ts';

export interface GoogleOAuthTokenFailure {
  readonly code: string;
  readonly message: string;
  readonly retryable: boolean;
}

export interface GoogleOAuthAccessTokenReader {
  readAccessToken(signal?: AbortSignal): Promise<Result<string, GoogleOAuthTokenFailure>>;
}

export type GooglePubSubFetch = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;

type BoundedResponseBodyFailure = 'cancelled' | 'read-failed' | 'too-large';

export type BoundedResponseBodyResult =
  | {
      readonly ok: true;
      readonly bytes: Uint8Array;
    }
  | {
      readonly ok: false;
      readonly failure: BoundedResponseBodyFailure;
    };

export interface GooglePubSubRestClientOptions {
  readonly fetch?: GooglePubSubFetch;
  readonly baseUrl?: string;
  readonly timeoutMs?: number;
}

interface GoogleSubscriptionJson {
  readonly name?: unknown;
  readonly messageRetentionDuration?: unknown;
  readonly deadLetterPolicy?: {
    readonly deadLetterTopic?: unknown;
    readonly maxDeliveryAttempts?: unknown;
  };
  readonly pushConfig?: {
    readonly pushEndpoint?: unknown;
    readonly oidcToken?: {
      readonly serviceAccountEmail?: unknown;
      readonly audience?: unknown;
    };
  };
}

const DEFAULT_BASE_URL = 'https://pubsub.googleapis.com';
const DEFAULT_TIMEOUT_MS = 10_000;
const MAX_RESPONSE_BYTES = 1_048_576;
const RESOURCE_NAME = /^projects\/[^/]+\/subscriptions\/[^/]+$/u;

export const cancelResponseBody = (response: Response): void => {
  try {
    void response.body?.cancel().catch(() => undefined);
  } catch {
    // Cancellation is best-effort and must not replace the sanitized failure.
  }
};

export const readBoundedResponseBody = async (
  response: Response,
  maxBytes: number,
  signal: AbortSignal,
): Promise<BoundedResponseBodyResult> => {
  const contentLength = response.headers.get('content-length');
  if (contentLength !== null && /^\d+$/u.test(contentLength) && Number(contentLength) > maxBytes) {
    cancelResponseBody(response);
    return { ok: false, failure: 'too-large' };
  }
  if (signal.aborted) {
    cancelResponseBody(response);
    return { ok: false, failure: 'cancelled' };
  }
  if (response.body === null) {
    return { ok: true, bytes: new Uint8Array() };
  }

  const reader = response.body.getReader();
  const cancelReader = (): void => {
    try {
      void reader.cancel().catch(() => undefined);
    } catch {
      // A concurrently completed stream does not need cancellation.
    }
  };
  let onAbort: (() => void) | undefined;
  const aborted = new Promise<{ readonly aborted: true }>(resolve => {
    onAbort = () => {
      cancelReader();
      resolve({ aborted: true });
    };
    signal.addEventListener('abort', onAbort, { once: true });
    if (signal.aborted) {
      onAbort();
    }
  });

  const chunks: Uint8Array[] = [];
  let byteLength = 0;
  try {
    while (true) {
      const next = await Promise.race([reader.read().then(read => ({ read })), aborted]);
      if ('aborted' in next) {
        return { ok: false, failure: 'cancelled' };
      }
      if (next.read.done) {
        break;
      }
      const chunk = next.read.value;
      if (chunk.byteLength > maxBytes - byteLength) {
        cancelReader();
        return { ok: false, failure: 'too-large' };
      }
      chunks.push(chunk);
      byteLength += chunk.byteLength;
    }
    if (signal.aborted) {
      cancelReader();
      return { ok: false, failure: 'cancelled' };
    }
  } catch {
    return {
      ok: false,
      failure: signal.aborted ? 'cancelled' : 'read-failed',
    };
  } finally {
    if (onAbort !== undefined) {
      signal.removeEventListener('abort', onAbort);
    }
    try {
      reader.releaseLock();
    } catch {
      // A pending read cancelled by the signal still owns the lock briefly.
    }
  }

  const bytes = new Uint8Array(byteLength);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return { ok: true, bytes };
};

const failure = (
  code: GooglePubSubAdminFailure['code'],
  message: string,
  retryable: boolean,
  status?: number,
): GooglePubSubAdminFailure => ({
  code,
  message,
  retryable,
  ...(status === undefined ? {} : { status }),
});

const parseDurationSeconds = (value: unknown): number | undefined => {
  if (typeof value !== 'string' || !/^\d+s$/u.test(value)) {
    return undefined;
  }
  const seconds = Number(value.slice(0, -1));
  return Number.isSafeInteger(seconds) ? seconds : undefined;
};

const parseSubscription = (input: unknown): Result<GooglePubSubSubscriptionState, GooglePubSubAdminFailure> => {
  if (input === null || typeof input !== 'object' || Array.isArray(input)) {
    return Err(failure('protocol', 'Google Pub/Sub returned an invalid subscription response', false));
  }
  const value = input as GoogleSubscriptionJson;
  const messageRetentionSeconds = parseDurationSeconds(value.messageRetentionDuration);
  if (typeof value.name !== 'string' || messageRetentionSeconds === undefined) {
    return Err(failure('protocol', 'Google Pub/Sub returned an invalid subscription response', false));
  }

  const deadLetterPolicy =
    typeof value.deadLetterPolicy?.deadLetterTopic === 'string' &&
    typeof value.deadLetterPolicy.maxDeliveryAttempts === 'number'
      ? {
          deadLetterTopic: value.deadLetterPolicy.deadLetterTopic,
          maxDeliveryAttempts: value.deadLetterPolicy.maxDeliveryAttempts,
        }
      : undefined;
  const pushConfig =
    typeof value.pushConfig?.pushEndpoint === 'string' &&
    typeof value.pushConfig.oidcToken?.serviceAccountEmail === 'string' &&
    typeof value.pushConfig.oidcToken.audience === 'string'
      ? {
          pushUrl: value.pushConfig.pushEndpoint,
          oidcServiceAccountEmail: value.pushConfig.oidcToken.serviceAccountEmail,
          oidcAudience: value.pushConfig.oidcToken.audience,
        }
      : undefined;
  return Ok({
    name: value.name,
    messageRetentionSeconds,
    ...(deadLetterPolicy === undefined ? {} : { deadLetterPolicy }),
    ...(pushConfig === undefined ? {} : { pushConfig }),
  });
};

const subscriptionJson = (name: string, desired: GooglePubSubDesiredState): Record<string, unknown> => ({
  name,
  messageRetentionDuration: `${desired.messageRetentionSeconds}s`,
  deadLetterPolicy: {
    deadLetterTopic: desired.deadLetterPolicy.deadLetterTopic,
    maxDeliveryAttempts: desired.deadLetterPolicy.maxDeliveryAttempts,
  },
  pushConfig: {
    pushEndpoint: desired.pushConfig.pushUrl,
    oidcToken: {
      serviceAccountEmail: desired.pushConfig.oidcServiceAccountEmail,
      audience: desired.pushConfig.oidcAudience,
    },
  },
});

export class FetchGooglePubSubAdministrationClient implements GooglePubSubAdministrationClient {
  readonly fetcher: GooglePubSubFetch;
  readonly baseUrl: string;
  readonly timeoutMs: number;

  constructor(
    readonly accessTokens: GoogleOAuthAccessTokenReader,
    options: GooglePubSubRestClientOptions = {},
  ) {
    this.fetcher = options.fetch ?? fetch;
    this.baseUrl = (options.baseUrl ?? DEFAULT_BASE_URL).replace(/\/+$/u, '');
    this.timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
    if (!Number.isSafeInteger(this.timeoutMs) || this.timeoutMs < 1 || this.timeoutMs > 30_000) {
      throw new RangeError('Google Pub/Sub timeout must be between 1 and 30000 milliseconds');
    }
  }

  async getSubscription(
    name: string,
    signal?: AbortSignal,
  ): Promise<Result<GooglePubSubSubscriptionState, GooglePubSubAdminFailure>> {
    const nameFailure = this.validateName(name);
    if (nameFailure !== undefined) {
      return Err(nameFailure);
    }
    return this.request(name, 'GET', undefined, signal);
  }

  async updateSubscription(
    input: {
      readonly name: string;
      readonly desired: GooglePubSubDesiredState;
      readonly updateMask: readonly GooglePubSubUpdateField[];
    },
    signal?: AbortSignal,
  ): Promise<Result<GooglePubSubSubscriptionState, GooglePubSubAdminFailure>> {
    const nameFailure = this.validateName(input.name);
    if (nameFailure !== undefined) {
      return Err(nameFailure);
    }
    return this.request(
      input.name,
      'PATCH',
      {
        subscription: subscriptionJson(input.name, input.desired),
        updateMask: input.updateMask.join(','),
      },
      signal,
    );
  }

  private validateName(name: string): GooglePubSubAdminFailure | undefined {
    return RESOURCE_NAME.test(name)
      ? undefined
      : failure('protocol', 'Google Pub/Sub subscription resource name is invalid', false);
  }

  private async request(
    resource: string,
    method: 'GET' | 'PATCH',
    body: Record<string, unknown> | undefined,
    signal?: AbortSignal,
  ): Promise<Result<GooglePubSubSubscriptionState, GooglePubSubAdminFailure>> {
    const externallyAborted = (): boolean => signal?.aborted === true;
    if (externallyAborted()) {
      return Err(failure('cancelled', 'Google Pub/Sub request was cancelled', true));
    }
    const tokenResult = await this.accessTokens.readAccessToken(signal);
    if (await tokenResult.isErr()) {
      const tokenFailure = await tokenResult.unwrapErr();
      return Err(failure('authentication', 'Google Pub/Sub OAuth access token is unavailable', tokenFailure.retryable));
    }
    const token = await tokenResult.unwrap();
    if (token.length === 0) {
      return Err(failure('authentication', 'Google Pub/Sub OAuth access token is unavailable', false));
    }

    const controller = new AbortController();
    let timedOut = false;
    const timeout = setTimeout(() => {
      timedOut = true;
      controller.abort();
    }, this.timeoutMs);
    const cancel = (): void => controller.abort();
    signal?.addEventListener('abort', cancel, { once: true });

    try {
      let response: Response;
      try {
        response = await this.fetcher(`${this.baseUrl}/v1/${resource}`, {
          method,
          headers: {
            Accept: 'application/json',
            Authorization: `Bearer ${token}`,
            ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
          },
          ...(body === undefined ? {} : { body: JSON.stringify(body) }),
          cache: 'no-store',
          credentials: 'omit',
          redirect: 'error',
          referrerPolicy: 'no-referrer',
          signal: controller.signal,
        });
      } catch {
        if (timedOut) {
          return Err(failure('timeout', 'Google Pub/Sub request timed out', true));
        }
        if (externallyAborted()) {
          return Err(failure('cancelled', 'Google Pub/Sub request was cancelled', true));
        }
        return Err(failure('network', 'Google Pub/Sub request could not connect', true));
      }

      if (controller.signal.aborted) {
        cancelResponseBody(response);
        if (timedOut) {
          return Err(failure('timeout', 'Google Pub/Sub request timed out', true));
        }
        return Err(failure('cancelled', 'Google Pub/Sub request was cancelled', true));
      }

      if (!response.ok) {
        cancelResponseBody(response);
        return Err(
          failure(
            'http',
            `Google Pub/Sub request failed with HTTP ${response.status}`,
            response.status === 408 || response.status === 429 || response.status >= 500,
            response.status,
          ),
        );
      }
      const bodyResult = await readBoundedResponseBody(response, MAX_RESPONSE_BYTES, controller.signal);
      if (!bodyResult.ok) {
        if (bodyResult.failure === 'cancelled') {
          return Err(
            timedOut
              ? failure('timeout', 'Google Pub/Sub request timed out', true)
              : failure('cancelled', 'Google Pub/Sub request was cancelled', true),
          );
        }
        if (bodyResult.failure === 'too-large') {
          return Err(failure('protocol', 'Google Pub/Sub response exceeded the size limit', false));
        }
        return Err(failure('network', 'Google Pub/Sub response could not be read', true));
      }
      let payload: unknown;
      try {
        payload = JSON.parse(new TextDecoder().decode(bodyResult.bytes)) as unknown;
      } catch {
        return Err(failure('protocol', 'Google Pub/Sub returned invalid JSON', false));
      }
      return parseSubscription(payload);
    } finally {
      clearTimeout(timeout);
      signal?.removeEventListener('abort', cancel);
    }
  }
}
