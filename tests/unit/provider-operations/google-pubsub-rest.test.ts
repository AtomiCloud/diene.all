import { describe, expect, test } from 'bun:test';
import { Err, Ok } from '@atomicloud/diene.result';
import {
  FetchGooglePubSubAdministrationClient,
  type GoogleOAuthAccessTokenReader,
} from '../../../src/provider-operations/google-pubsub-rest.ts';
import type { GooglePubSubDesiredState } from '../../../src/provider-operations/google-rtdn-reconciler.ts';

const name = 'projects/atomi/subscriptions/google-play';
const token = 'ya29.production-secret';
const desired: GooglePubSubDesiredState = {
  messageRetentionSeconds: 2_678_400,
  deadLetterPolicy: {
    deadLetterTopic: 'projects/atomi/topics/google-play-dead-letter',
    maxDeliveryAttempts: 12,
  },
  pushConfig: {
    pushUrl: 'https://hooks.example.test/t/acme/google-play',
    oidcServiceAccountEmail: 'push@atomi.iam.gserviceaccount.com',
    oidcAudience: 'https://hooks.example.test/t/acme/google-play',
  },
};

const responseBody = {
  name,
  messageRetentionDuration: '2678400s',
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
};

const tokenReader: GoogleOAuthAccessTokenReader = {
  readAccessToken: async () => Ok(token),
};

describe('fetch Google Pub/Sub administration adapter', () => {
  test('sends the exact REST patch with OAuth and parses repair evidence', async () => {
    const requests: Array<{ url: string; init?: RequestInit }> = [];
    const fetcher = async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
      requests.push({
        url: String(input),
        ...(init === undefined ? {} : { init }),
      });
      return new Response(JSON.stringify(responseBody), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      });
    };
    const client = new FetchGooglePubSubAdministrationClient(tokenReader, {
      fetch: fetcher,
      baseUrl: 'https://pubsub.example.test/',
      timeoutMs: 1_000,
    });

    const result = await client.updateSubscription({
      name,
      desired,
      updateMask: ['messageRetentionDuration', 'deadLetterPolicy', 'pushConfig'],
    });
    expect(await result.unwrap()).toEqual({ name, ...desired });
    expect(requests).toHaveLength(1);
    const request = requests[0];
    expect(request?.url).toBe('https://pubsub.example.test/v1/projects/atomi/subscriptions/google-play');
    expect(request?.init?.method).toBe('PATCH');
    expect(request?.init?.headers).toMatchObject({
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    });
    expect(JSON.parse(String(request?.init?.body))).toEqual({
      subscription: {
        name,
        messageRetentionDuration: '2678400s',
        deadLetterPolicy: {
          deadLetterTopic: desired.deadLetterPolicy.deadLetterTopic,
          maxDeliveryAttempts: 12,
        },
        pushConfig: {
          pushEndpoint: desired.pushConfig.pushUrl,
          oidcToken: {
            serviceAccountEmail: desired.pushConfig.oidcServiceAccountEmail,
            audience: desired.pushConfig.oidcAudience,
          },
        },
      },
      updateMask: 'messageRetentionDuration,deadLetterPolicy,pushConfig',
    });
  });

  test('bounds requests with a timeout', async () => {
    const fetcher = (_input: string | URL | Request, init?: RequestInit): Promise<Response> =>
      new Promise((_resolve, reject) => {
        init?.signal?.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')), {
          once: true,
        });
      });
    const client = new FetchGooglePubSubAdministrationClient(tokenReader, {
      fetch: fetcher,
      timeoutMs: 5,
    });
    const result = await client.getSubscription(name);
    expect(await result.unwrapErr()).toMatchObject({
      code: 'timeout',
      retryable: true,
    });
  });

  test('keeps timeout and caller cancellation active while a chunked body is stalled', async () => {
    let timeoutBodyCancelled = false;
    const timedClient = new FetchGooglePubSubAdministrationClient(tokenReader, {
      fetch: async () =>
        new Response(
          new ReadableStream<Uint8Array>({
            start(controller) {
              controller.enqueue(new TextEncoder().encode('{"name":'));
            },
            cancel() {
              timeoutBodyCancelled = true;
            },
          }),
          { status: 200 },
        ),
      timeoutMs: 5,
    });
    expect(await (await timedClient.getSubscription(name)).unwrapErr()).toMatchObject({
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
    const cancellableClient = new FetchGooglePubSubAdministrationClient(tokenReader, {
      fetch: async () =>
        new Response(
          new ReadableStream<Uint8Array>({
            start(bodyController) {
              bodyController.enqueue(new TextEncoder().encode('{"name":'));
              markCallerBodyStarted();
            },
            cancel() {
              callerBodyCancelled = true;
            },
          }),
          { status: 200 },
        ),
      timeoutMs: 1_000,
    });
    const pending = cancellableClient.getSubscription(name, controller.signal);
    await callerBodyStarted;
    controller.abort();
    expect(await (await pending).unwrapErr()).toMatchObject({
      code: 'cancelled',
      retryable: true,
    });
    expect(callerBodyCancelled).toBeTrue();
  });

  test('cancels a dishonest chunked response as soon as the actual body exceeds its cap', async () => {
    let bodyCancelled = false;
    const client = new FetchGooglePubSubAdministrationClient(tokenReader, {
      fetch: async () =>
        new Response(
          new ReadableStream<Uint8Array>({
            start(controller) {
              controller.enqueue(new Uint8Array(1_048_577));
            },
            cancel() {
              bodyCancelled = true;
            },
          }),
          {
            status: 200,
            headers: { 'content-type': 'application/json' },
          },
        ),
    });

    expect(await (await client.getSubscription(name)).unwrapErr()).toMatchObject({
      code: 'protocol',
      retryable: false,
    });
    expect(bodyCancelled).toBeTrue();
  });

  test('never exposes token-reader, transport, or HTTP response secrets', async () => {
    const secret = 'ya29.should-never-escape';
    const failedTokenReader: GoogleOAuthAccessTokenReader = {
      readAccessToken: async () =>
        Err({
          code: 'vault',
          message: `could not read ${secret}`,
          retryable: true,
        }),
    };
    const authentication = await new FetchGooglePubSubAdministrationClient(failedTokenReader).getSubscription(name);
    expect(JSON.stringify(await authentication.unwrapErr())).not.toContain(secret);

    const httpClient = new FetchGooglePubSubAdministrationClient(tokenReader, {
      fetch: async () =>
        new Response(`rejected credential ${secret}`, {
          status: 401,
        }),
    });
    const http = await httpClient.getSubscription(name);
    const httpFailure = await http.unwrapErr();
    expect(httpFailure).toMatchObject({
      code: 'http',
      status: 401,
      retryable: false,
    });
    expect(JSON.stringify(httpFailure)).not.toContain(secret);

    const networkClient = new FetchGooglePubSubAdministrationClient(tokenReader, {
      fetch: async () => {
        throw new Error(`transport leaked ${secret}`);
      },
    });
    const network = await networkClient.getSubscription(name);
    expect(JSON.stringify(await network.unwrapErr())).not.toContain(secret);
  });

  test('rejects malformed resource names and protocol responses', async () => {
    const fetcher = async () =>
      new Response(JSON.stringify({ name, messageRetentionDuration: '31d' }), {
        status: 200,
      });
    const client = new FetchGooglePubSubAdministrationClient(tokenReader, {
      fetch: fetcher,
    });
    expect(await (await client.getSubscription('not-a-resource')).unwrapErr()).toMatchObject({ code: 'protocol' });
    expect(await (await client.getSubscription(name)).unwrapErr()).toMatchObject({
      code: 'protocol',
    });
  });
});
