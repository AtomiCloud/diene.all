import { describe, expect, test } from 'bun:test';
import { Ok } from '@atomicloud/diene.result';
import { exportPKCS8, generateKeyPair, jwtVerify } from 'jose';
import {
  type AppleAppStoreServerTokenProvider,
  createAppleAppStoreNotificationHistoryClient,
  FetchAppleAppStoreNotificationHistoryClient,
} from '../../../src/provider-operations/apple-history-rest.ts';
import { MemorySecretReader } from '../../../src/runtime/fakes.ts';

const encoder = new TextEncoder();
const issuerId = '57246542-96fe-1a63-e053-0824d011072a';
const keyId = 'ABCDEFGHIJ';
const bundleId = 'cloud.atomi.mercury';
const signingKeySecretRef = 'apple-app-store-history.p8';
const nowMs = Date.parse('2026-07-29T02:00:00.000Z');
const historyRequest = {
  startDateMs: Date.parse('2026-07-28T00:00:00.000Z'),
  endDateMs: Date.parse('2026-07-29T00:00:00.000Z'),
  onlyFailures: false,
  transactionId: 'transaction-1',
  notificationType: 'DID_RENEW',
  subtype: 'BILLING_RECOVERY',
};

describe('Apple App Store notification-history REST adapter', () => {
  test('signs an ES256 authorization JWT and maps page-level pagination', async () => {
    const { privateKey, publicKey } = await generateKeyPair('ES256', {
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
          notificationHistory: [
            { signedPayload: 'signed-one', sendAttempts: [] },
            { signedPayload: 'signed-two', sendAttempts: [] },
          ],
          hasMore: true,
          paginationToken: 'next-page-token',
        }),
        { status: 200 },
      );
    };
    const client = createAppleAppStoreNotificationHistoryClient(
      new MemorySecretReader({
        [signingKeySecretRef]: encoder.encode(privateKeyPem),
      }),
      { nowMs: () => nowMs },
      {
        issuerId,
        keyId,
        bundleId,
        signingKeySecretRef,
      },
      {
        environment: 'Sandbox',
        request: historyRequest,
        fetch: fetcher,
      },
    );

    const result = await client.listNotifications({
      cursor: 'current-page-token',
      limit: 100,
      signal: new AbortController().signal,
    });
    expect(await result.unwrap()).toEqual({
      notifications: [{ signedPayload: 'signed-one' }, { signedPayload: 'signed-two' }],
      hasMore: true,
      cursorAfter: 'next-page-token',
    });
    const request = requests[0];
    expect(request?.url).toBe(
      'https://api.storekit-sandbox.apple.com/inApps/v1/notifications/history?paginationToken=current-page-token',
    );
    expect(request?.init?.method).toBe('POST');
    expect(JSON.parse(String(request?.init?.body))).toEqual({
      startDate: historyRequest.startDateMs,
      endDate: historyRequest.endDateMs,
      onlyFailures: false,
      transactionId: 'transaction-1',
      notificationType: 'DID_RENEW',
      subtype: 'BILLING_RECOVERY',
    });
    const authorization = (request?.init?.headers as Record<string, string>)?.Authorization;
    expect(authorization).toStartWith('Bearer ');
    const verified = await jwtVerify((authorization ?? '').slice('Bearer '.length), publicKey, {
      algorithms: ['ES256'],
      issuer: issuerId,
      audience: 'appstoreconnect-v1',
      currentDate: new Date(nowMs),
    });
    expect(verified.protectedHeader).toMatchObject({
      alg: 'ES256',
      kid: keyId,
      typ: 'JWT',
    });
    expect(verified.payload).toMatchObject({
      bid: bundleId,
      iat: Math.floor(nowMs / 1_000),
      exp: Math.floor(nowMs / 1_000) + 300,
    });
  });

  test('rejects forged signing material and malformed history without exposing it', async () => {
    const forgedKey = '-----BEGIN PRIVATE KEY-----\nforged-secret\n-----END PRIVATE KEY-----';
    const forgedClient = createAppleAppStoreNotificationHistoryClient(
      new MemorySecretReader({
        [signingKeySecretRef]: encoder.encode(forgedKey),
      }),
      { nowMs: () => nowMs },
      {
        issuerId,
        keyId,
        bundleId,
        signingKeySecretRef,
      },
      {
        environment: 'Production',
        request: historyRequest,
        fetch: async () => {
          throw new Error('fetch must not run');
        },
      },
    );
    const forged = await forgedClient.listNotifications({
      limit: 20,
      signal: new AbortController().signal,
    });
    const forgedFailure = await forged.unwrapErr();
    expect(forgedFailure).toMatchObject({
      code: 'authentication',
      retryable: false,
    });
    expect(JSON.stringify(forgedFailure)).not.toContain('forged-secret');

    const tokenProvider: AppleAppStoreServerTokenProvider = {
      createToken: async () => Ok('secret-authorization-token'),
    };
    const malformedClient = new FetchAppleAppStoreNotificationHistoryClient(tokenProvider, {
      environment: 'Production',
      request: historyRequest,
      fetch: async () =>
        new Response(
          JSON.stringify({
            notificationHistory: [{ signedPayload: '' }],
            hasMore: false,
            paginationToken: 'next',
          }),
          { status: 200 },
        ),
    });
    const malformed = await malformedClient.listNotifications({
      limit: 20,
      signal: new AbortController().signal,
    });
    expect(await malformed.unwrapErr()).toMatchObject({ code: 'protocol' });

    const rejectedClient = new FetchAppleAppStoreNotificationHistoryClient(tokenProvider, {
      environment: 'Production',
      request: historyRequest,
      fetch: async () =>
        new Response('secret-authorization-token rejected', {
          status: 401,
        }),
    });
    const rejected = await rejectedClient.listNotifications({
      limit: 20,
      signal: new AbortController().signal,
    });
    expect(JSON.stringify(await rejected.unwrapErr())).not.toContain('secret-authorization-token');

    let productionUrl = '';
    const oversizedClient = new FetchAppleAppStoreNotificationHistoryClient(tokenProvider, {
      environment: 'Production',
      request: historyRequest,
      maxResponseBytes: 8,
      fetch: async input => {
        productionUrl = String(input);
        return new Response('response-is-too-large', { status: 200 });
      },
    });
    const oversized = await oversizedClient.listNotifications({
      limit: 20,
      signal: new AbortController().signal,
    });
    expect(await oversized.unwrapErr()).toMatchObject({ code: 'protocol' });
    expect(productionUrl).toBe('https://api.storekit.apple.com/inApps/v1/notifications/history');
  });

  test('bounds fetch time and honors caller cancellation', async () => {
    const tokenProvider: AppleAppStoreServerTokenProvider = {
      createToken: async () => Ok('authorization-token'),
    };
    const pendingFetch = (_input: string | URL | Request, init?: RequestInit): Promise<Response> =>
      new Promise((_resolve, reject) => {
        init?.signal?.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')), {
          once: true,
        });
      });
    const timedClient = new FetchAppleAppStoreNotificationHistoryClient(tokenProvider, {
      environment: 'Production',
      request: historyRequest,
      timeoutMs: 5,
      fetch: pendingFetch,
    });
    const timed = await timedClient.listNotifications({
      limit: 20,
      signal: new AbortController().signal,
    });
    expect(await timed.unwrapErr()).toMatchObject({ code: 'timeout' });

    const controller = new AbortController();
    const cancelledPromise = new FetchAppleAppStoreNotificationHistoryClient(tokenProvider, {
      environment: 'Sandbox',
      request: historyRequest,
      timeoutMs: 1_000,
      fetch: pendingFetch,
    }).listNotifications({
      limit: 20,
      signal: controller.signal,
    });
    controller.abort();
    expect(await (await cancelledPromise).unwrapErr()).toMatchObject({
      code: 'cancelled',
    });
  });

  test('keeps cancellation active through slow bodies and cancels dishonest oversized streams', async () => {
    const tokenProvider: AppleAppStoreServerTokenProvider = {
      createToken: async () => Ok('authorization-token'),
    };
    let timeoutBodyCancelled = false;
    const timedClient = new FetchAppleAppStoreNotificationHistoryClient(tokenProvider, {
      environment: 'Production',
      request: historyRequest,
      timeoutMs: 5,
      fetch: async () =>
        new Response(
          new ReadableStream<Uint8Array>({
            start(controller) {
              controller.enqueue(encoder.encode('{"notificationHistory":'));
            },
            cancel() {
              timeoutBodyCancelled = true;
            },
          }),
          { status: 200 },
        ),
    });
    expect(
      await (
        await timedClient.listNotifications({
          limit: 20,
          signal: new AbortController().signal,
        })
      ).unwrapErr(),
    ).toMatchObject({ code: 'timeout', retryable: true });
    expect(timeoutBodyCancelled).toBeTrue();

    let callerBodyCancelled = false;
    let markCallerBodyStarted: () => void = () => undefined;
    const callerBodyStarted = new Promise<void>(resolve => {
      markCallerBodyStarted = resolve;
    });
    const callerController = new AbortController();
    const cancellableClient = new FetchAppleAppStoreNotificationHistoryClient(tokenProvider, {
      environment: 'Sandbox',
      request: historyRequest,
      timeoutMs: 1_000,
      fetch: async () =>
        new Response(
          new ReadableStream<Uint8Array>({
            start(controller) {
              controller.enqueue(encoder.encode('{"notificationHistory":'));
              markCallerBodyStarted();
            },
            cancel() {
              callerBodyCancelled = true;
            },
          }),
          { status: 200 },
        ),
    });
    const cancelled = cancellableClient.listNotifications({
      limit: 20,
      signal: callerController.signal,
    });
    await callerBodyStarted;
    callerController.abort();
    expect(await (await cancelled).unwrapErr()).toMatchObject({
      code: 'cancelled',
      retryable: true,
    });
    expect(callerBodyCancelled).toBeTrue();

    let oversizedBodyCancelled = false;
    const oversizedClient = new FetchAppleAppStoreNotificationHistoryClient(tokenProvider, {
      environment: 'Production',
      request: historyRequest,
      maxResponseBytes: 8,
      fetch: async () =>
        new Response(
          new ReadableStream<Uint8Array>({
            start(controller) {
              controller.enqueue(encoder.encode('dishonest-body'));
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
    });
    expect(
      await (
        await oversizedClient.listNotifications({
          limit: 20,
          signal: new AbortController().signal,
        })
      ).unwrapErr(),
    ).toMatchObject({ code: 'protocol', retryable: false });
    expect(oversizedBodyCancelled).toBeTrue();
  });
});
