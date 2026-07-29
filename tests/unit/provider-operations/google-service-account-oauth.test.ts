import { describe, expect, test } from 'bun:test';
import { Ok } from '@atomicloud/diene.result';
import { exportPKCS8, generateKeyPair, jwtVerify } from 'jose';
import {
  createGoogleServiceAccountOAuthAccessTokenReader,
  GOOGLE_CLOUD_PLATFORM_OAUTH_SCOPE,
  GOOGLE_PUBSUB_OAUTH_SCOPE,
  type GoogleServiceAccountAssertionSigner,
  SecretBackedGoogleOAuthAccessTokenReader,
} from '../../../src/provider-operations/google-service-account-oauth.ts';
import { MemorySecretReader } from '../../../src/runtime/fakes.ts';

const encoder = new TextEncoder();
const credentialRef = 'google-pubsub-service-account.json';
const clientEmail = 'mercury-pubsub@atomi.iam.gserviceaccount.com';
const nowMs = Date.parse('2026-07-29T02:00:00.000Z');

const credentialJson = (privateKeyPem: string, overrides: Readonly<Record<string, unknown>> = {}): Uint8Array =>
  encoder.encode(
    JSON.stringify({
      type: 'service_account',
      project_id: 'atomi',
      private_key_id: 'service-account-key-id',
      private_key: privateKeyPem,
      client_email: clientEmail,
      token_uri: 'https://oauth2.googleapis.com/token',
      ...overrides,
    }),
  );

describe('Google service-account OAuth access-token reader', () => {
  test('signs the official RS256 assertion and exchanges it for a scoped token', async () => {
    const { privateKey, publicKey } = await generateKeyPair('RS256', {
      extractable: true,
    });
    const privateKeyPem = await exportPKCS8(privateKey);
    const requests: Array<{ url: string; init?: RequestInit }> = [];
    const fetcher = async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
      requests.push({
        url: String(input),
        ...(init === undefined ? {} : { init }),
      });
      return new Response(
        JSON.stringify({
          access_token: 'oauth-access-token',
          token_type: 'Bearer',
          expires_in: 3_600,
          scope: `${GOOGLE_PUBSUB_OAUTH_SCOPE} ${GOOGLE_CLOUD_PLATFORM_OAUTH_SCOPE}`,
        }),
        { status: 200 },
      );
    };
    const reader = createGoogleServiceAccountOAuthAccessTokenReader(
      new MemorySecretReader({
        [credentialRef]: credentialJson(privateKeyPem),
      }),
      { nowMs: () => nowMs },
      {
        credentialSecretRef: credentialRef,
        expectedServiceAccountEmail: clientEmail,
        scopes: [GOOGLE_PUBSUB_OAUTH_SCOPE, GOOGLE_CLOUD_PLATFORM_OAUTH_SCOPE],
        fetch: fetcher,
      },
    );

    expect(await (await reader.readAccessToken()).unwrap()).toBe('oauth-access-token');
    const request = requests[0];
    expect(request?.url).toBe('https://oauth2.googleapis.com/token');
    expect(request?.init?.method).toBe('POST');
    expect(request?.init?.headers).toMatchObject({
      'Content-Type': 'application/x-www-form-urlencoded',
    });
    const form = new URLSearchParams(String(request?.init?.body));
    expect(form.get('grant_type')).toBe('urn:ietf:params:oauth:grant-type:jwt-bearer');
    const assertion = form.get('assertion');
    expect(assertion).not.toBeNull();
    const verified = await jwtVerify(assertion ?? '', publicKey, {
      algorithms: ['RS256'],
      issuer: clientEmail,
      audience: 'https://oauth2.googleapis.com/token',
      currentDate: new Date(nowMs),
    });
    expect(verified.protectedHeader).toMatchObject({
      alg: 'RS256',
      typ: 'JWT',
      kid: 'service-account-key-id',
    });
    expect(verified.payload).toMatchObject({
      scope: `${GOOGLE_PUBSUB_OAUTH_SCOPE} ${GOOGLE_CLOUD_PLATFORM_OAUTH_SCOPE}`,
      iat: Math.floor(nowMs / 1_000),
      exp: Math.floor(nowMs / 1_000) + 3_600,
    });
  });

  test('caches until the expiry skew and refreshes afterward', async () => {
    const { privateKey } = await generateKeyPair('RS256', {
      extractable: true,
    });
    const privateKeyPem = await exportPKCS8(privateKey);
    let currentMs = nowMs;
    let requests = 0;
    const reader = new SecretBackedGoogleOAuthAccessTokenReader(
      new MemorySecretReader({
        [credentialRef]: credentialJson(privateKeyPem),
      }),
      { nowMs: () => currentMs },
      {
        credentialSecretRef: credentialRef,
        expectedServiceAccountEmail: clientEmail,
        cacheSkewMs: 10_000,
        fetch: async () => {
          requests += 1;
          return new Response(
            JSON.stringify({
              access_token: `token-${requests}`,
              token_type: 'Bearer',
              expires_in: 120,
              scope: GOOGLE_PUBSUB_OAUTH_SCOPE,
            }),
            { status: 200 },
          );
        },
      },
    );

    expect(await (await reader.readAccessToken()).unwrap()).toBe('token-1');
    currentMs += 100_000;
    expect(await (await reader.readAccessToken()).unwrap()).toBe('token-1');
    expect(requests).toBe(1);
    currentMs += 10_000;
    expect(await (await reader.readAccessToken()).unwrap()).toBe('token-2');
    expect(requests).toBe(2);
  });

  test('rejects substituted or malformed credentials without exposing them', async () => {
    const { privateKey } = await generateKeyPair('RS256', {
      extractable: true,
    });
    const privateKeyPem = await exportPKCS8(privateKey);
    const forgedEmail = 'forged@attacker.iam.gserviceaccount.com';
    const forged = new SecretBackedGoogleOAuthAccessTokenReader(
      new MemorySecretReader({
        [credentialRef]: credentialJson(privateKeyPem, {
          client_email: forgedEmail,
        }),
      }),
      { nowMs: () => nowMs },
      {
        credentialSecretRef: credentialRef,
        expectedServiceAccountEmail: clientEmail,
        fetch: async () => {
          throw new Error('fetch must not run');
        },
      },
    );
    const forgedFailure = await (await forged.readAccessToken()).unwrapErr();
    expect(forgedFailure).toMatchObject({
      code: 'credential',
      retryable: false,
    });
    expect(JSON.stringify(forgedFailure)).not.toContain(forgedEmail);

    const malformedKey =
      '-----BEGIN PRIVATE KEY-----\nprivate-key-secret-that-must-not-escape\n-----END PRIVATE KEY-----';
    const malformed = new SecretBackedGoogleOAuthAccessTokenReader(
      new MemorySecretReader({
        [credentialRef]: credentialJson(malformedKey),
      }),
      { nowMs: () => nowMs },
      {
        credentialSecretRef: credentialRef,
        expectedServiceAccountEmail: clientEmail,
      },
    );
    const malformedFailure = await (await malformed.readAccessToken()).unwrapErr();
    expect(JSON.stringify(malformedFailure)).not.toContain(malformedKey);
  });

  test('bounds token exchange, honors cancellation, and contains remote errors', async () => {
    const { privateKey } = await generateKeyPair('RS256', {
      extractable: true,
    });
    const privateKeyPem = await exportPKCS8(privateKey);
    const secrets = new MemorySecretReader({
      [credentialRef]: credentialJson(privateKeyPem),
    });
    const pendingFetch = (_input: string | URL | Request, init?: RequestInit): Promise<Response> =>
      new Promise((_resolve, reject) => {
        init?.signal?.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')), {
          once: true,
        });
      });
    const timed = new SecretBackedGoogleOAuthAccessTokenReader(
      secrets,
      { nowMs: () => nowMs },
      {
        credentialSecretRef: credentialRef,
        expectedServiceAccountEmail: clientEmail,
        timeoutMs: 5,
        fetch: pendingFetch,
      },
    );
    expect(await (await timed.readAccessToken()).unwrapErr()).toMatchObject({
      code: 'timeout',
    });

    const controller = new AbortController();
    const cancellable = new SecretBackedGoogleOAuthAccessTokenReader(
      secrets,
      { nowMs: () => nowMs },
      {
        credentialSecretRef: credentialRef,
        expectedServiceAccountEmail: clientEmail,
        timeoutMs: 1_000,
        fetch: pendingFetch,
      },
    );
    const cancelledPromise = cancellable.readAccessToken(controller.signal);
    controller.abort();
    expect(await (await cancelledPromise).unwrapErr()).toMatchObject({
      code: 'cancelled',
    });

    const remoteSecret = 'remote-secret-must-not-escape';
    const rejected = new SecretBackedGoogleOAuthAccessTokenReader(
      secrets,
      { nowMs: () => nowMs },
      {
        credentialSecretRef: credentialRef,
        expectedServiceAccountEmail: clientEmail,
        fetch: async () =>
          new Response(remoteSecret, {
            status: 401,
          }),
      },
    );
    const rejectedFailure = await (await rejected.readAccessToken()).unwrapErr();
    expect(rejectedFailure).toMatchObject({ code: 'http', retryable: false });
    expect(JSON.stringify(rejectedFailure)).not.toContain(remoteSecret);

    const oversized = new SecretBackedGoogleOAuthAccessTokenReader(
      secrets,
      { nowMs: () => nowMs },
      {
        credentialSecretRef: credentialRef,
        expectedServiceAccountEmail: clientEmail,
        maxResponseBytes: 8,
        fetch: async () => new Response('response-is-too-large', { status: 200 }),
      },
    );
    expect(await (await oversized.readAccessToken()).unwrapErr()).toMatchObject({
      code: 'protocol',
    });
  });

  test('keeps timeout and caller cancellation active through bounded token-response streaming', async () => {
    const { privateKey } = await generateKeyPair('RS256', {
      extractable: true,
    });
    const privateKeyPem = await exportPKCS8(privateKey);
    const secrets = new MemorySecretReader({
      [credentialRef]: credentialJson(privateKeyPem),
    });
    const signer: GoogleServiceAccountAssertionSigner = {
      signAssertion: async () => Ok('signed-assertion'),
    };
    let timeoutBodyCancelled = false;
    const timed = new SecretBackedGoogleOAuthAccessTokenReader(
      secrets,
      { nowMs: () => nowMs },
      {
        credentialSecretRef: credentialRef,
        expectedServiceAccountEmail: clientEmail,
        timeoutMs: 50,
        fetch: async () =>
          new Response(
            new ReadableStream<Uint8Array>({
              start(controller) {
                controller.enqueue(encoder.encode('{"access_token":'));
              },
              cancel() {
                timeoutBodyCancelled = true;
              },
            }),
            { status: 200 },
          ),
      },
      signer,
    );
    expect(await (await timed.readAccessToken()).unwrapErr()).toMatchObject({
      code: 'timeout',
      retryable: true,
    });
    expect(timeoutBodyCancelled).toBeTrue();

    let callerBodyCancelled = false;
    let markCallerBodyStarted: () => void = () => undefined;
    const callerBodyStarted = new Promise<void>(resolve => {
      markCallerBodyStarted = resolve;
    });
    const controller = new AbortController();
    const cancellable = new SecretBackedGoogleOAuthAccessTokenReader(
      secrets,
      { nowMs: () => nowMs },
      {
        credentialSecretRef: credentialRef,
        expectedServiceAccountEmail: clientEmail,
        timeoutMs: 1_000,
        fetch: async () =>
          new Response(
            new ReadableStream<Uint8Array>({
              start(bodyController) {
                bodyController.enqueue(encoder.encode('{"access_token":'));
                markCallerBodyStarted();
              },
              cancel() {
                callerBodyCancelled = true;
              },
            }),
            { status: 200 },
          ),
      },
      signer,
    );
    const cancelled = cancellable.readAccessToken(controller.signal);
    await callerBodyStarted;
    controller.abort();
    expect(await (await cancelled).unwrapErr()).toMatchObject({
      code: 'cancelled',
      retryable: true,
    });
    expect(callerBodyCancelled).toBeTrue();

    let oversizedBodyCancelled = false;
    const oversized = new SecretBackedGoogleOAuthAccessTokenReader(
      secrets,
      { nowMs: () => nowMs },
      {
        credentialSecretRef: credentialRef,
        expectedServiceAccountEmail: clientEmail,
        maxResponseBytes: 8,
        fetch: async () =>
          new Response(
            new ReadableStream<Uint8Array>({
              start(bodyController) {
                bodyController.enqueue(encoder.encode('dishonest-body'));
              },
              cancel() {
                oversizedBodyCancelled = true;
              },
            }),
            {
              status: 200,
              headers: { 'content-type': 'application/json' },
            },
          ),
      },
      signer,
    );
    expect(await (await oversized.readAccessToken()).unwrapErr()).toMatchObject({
      code: 'protocol',
      retryable: false,
    });
    expect(oversizedBodyCancelled).toBeTrue();
  });

  test('validates approved scopes and token-response scope evidence', async () => {
    expect(
      () =>
        new SecretBackedGoogleOAuthAccessTokenReader(
          new MemorySecretReader({
            [credentialRef]: encoder.encode('{}'),
          }),
          { nowMs: () => nowMs },
          {
            credentialSecretRef: credentialRef,
            expectedServiceAccountEmail: clientEmail,
            scopes: ['https://www.googleapis.com/auth/drive'] as never,
          },
        ),
    ).toThrow();

    const { privateKey } = await generateKeyPair('RS256', {
      extractable: true,
    });
    const privateKeyPem = await exportPKCS8(privateKey);
    const reader = new SecretBackedGoogleOAuthAccessTokenReader(
      new MemorySecretReader({
        [credentialRef]: credentialJson(privateKeyPem),
      }),
      { nowMs: () => nowMs },
      {
        credentialSecretRef: credentialRef,
        expectedServiceAccountEmail: clientEmail,
        fetch: async () =>
          new Response(
            JSON.stringify({
              access_token: 'token',
              token_type: 'Bearer',
              expires_in: 3_600,
              scope: GOOGLE_CLOUD_PLATFORM_OAUTH_SCOPE,
            }),
            { status: 200 },
          ),
      },
    );
    expect(await (await reader.readAccessToken()).unwrapErr()).toMatchObject({
      code: 'protocol',
      message: 'Google OAuth token response omitted a required scope',
    });
  });
});
