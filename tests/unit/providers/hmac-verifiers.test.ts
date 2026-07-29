import { describe, expect, test } from 'bun:test';
import { createHmac } from 'node:crypto';
import {
  airwallexVerifier,
  logtoVerifier,
  stripeVerifier,
  telegramVerifier,
  type VerificationRequest,
} from '../../../src/providers/index.ts';

const encoder = new TextEncoder();
const registeredUrl = 'https://hooks.webhook.mercury.mew.cluster.atomi.cloud/t/acme/payments';
const now = new Date('2026-07-29T00:10:00.000Z');

const body = (value: unknown): Uint8Array => encoder.encode(JSON.stringify(value));

const request = (rawBody: Uint8Array, headers: Readonly<Record<string, string>>): VerificationRequest => ({
  rawBody,
  headers,
  registeredUrl,
  receivedAt: now,
});

const hmac = (secret: string, ...parts: readonly (string | Uint8Array)[]): string => {
  const digest = createHmac('sha256', secret);
  for (const part of parts) {
    digest.update(part);
  }
  return digest.digest('hex');
};

describe('Stripe verifier', () => {
  const secret = 'whsec_mercury_test_secret';
  const timestamp = Math.floor(now.getTime() / 1_000);

  test('verifies raw bytes with a dual-live secret and returns the native ID', async () => {
    const rawBody = body({
      id: 'evt_1PzzVnMercury',
      object: 'event',
      type: 'checkout.session.completed',
      created: timestamp - 1,
    });
    const signature = hmac(secret, `${timestamp}.`, rawBody);

    const result = await stripeVerifier.verify(
      request(rawBody, {
        'stripe-signature': `t=${timestamp},v1=${signature},v0=legacy`,
      }),
      { secrets: ['next-secret', secret] },
    );

    expect(result).toMatchObject({
      provider: 'stripe',
      dedupId: 'evt_1PzzVnMercury',
      metadata: {
        eventId: 'evt_1PzzVnMercury',
        eventType: 'checkout.session.completed',
        providerTimestamp: (timestamp - 1) * 1_000,
      },
    });
  });

  test('rejects forged signatures', async () => {
    const rawBody = body({ id: 'evt_forged' });

    await expect(
      stripeVerifier.verify(
        request(rawBody, {
          'Stripe-Signature': `t=${timestamp},v1=${'0'.repeat(64)}`,
        }),
        { secrets: [secret] },
      ),
    ).rejects.toMatchObject({ code: 'invalid_signature' });
  });

  test('rejects a valid but stale signed timestamp', async () => {
    const staleTimestamp = timestamp - 301;
    const rawBody = body({ id: 'evt_stale' });
    const signature = hmac(secret, `${staleTimestamp}.`, rawBody);

    await expect(
      stripeVerifier.verify(
        request(rawBody, {
          'Stripe-Signature': `t=${staleTimestamp},v1=${signature}`,
        }),
        { secrets: [secret] },
      ),
    ).rejects.toMatchObject({ code: 'timestamp_skew' });
  });

  test('rejects malformed signature headers', async () => {
    await expect(
      stripeVerifier.verify(
        request(body({ id: 'evt_bad_header' }), {
          'Stripe-Signature': 'v1=missing-timestamp',
        }),
        { secrets: [secret] },
      ),
    ).rejects.toMatchObject({ code: 'malformed_header' });
  });
});

describe('Airwallex verifier', () => {
  const secret = 'airwallex-notification-secret';
  const timestamp = String(now.getTime());

  test('verifies timestamp plus raw body and returns Airwallex event metadata', async () => {
    const rawBody = body({
      id: 'evt_100_2019102201540902013102020043_8321220011893766',
      name: 'payment_attempt.authorized',
      created_at: '2026-07-29T00:09:59.000Z',
      data: { object: { id: 'pay_123' } },
    });
    const signature = hmac(secret, timestamp, rawBody);

    const result = await airwallexVerifier.verify(
      request(rawBody, {
        'x-timestamp': timestamp,
        'x-signature': signature,
      }),
      { secrets: [secret] },
    );

    expect(result.dedupId).toBe('evt_100_2019102201540902013102020043_8321220011893766');
    expect(result.metadata).toEqual({
      eventId: 'evt_100_2019102201540902013102020043_8321220011893766',
      eventType: 'payment_attempt.authorized',
      providerTimestamp: now.getTime() - 1_000,
    });
  });

  test('rejects forged signatures and valid stale requests', async () => {
    const rawBody = body({ id: 'evt_airwallex' });

    await expect(
      airwallexVerifier.verify(
        request(rawBody, {
          'x-timestamp': timestamp,
          'x-signature': 'f'.repeat(64),
        }),
        { secrets: [secret] },
      ),
    ).rejects.toMatchObject({ code: 'invalid_signature' });

    const staleTimestamp = String(now.getTime() - 301_000);
    await expect(
      airwallexVerifier.verify(
        request(rawBody, {
          'x-timestamp': staleTimestamp,
          'x-signature': hmac(secret, staleTimestamp, rawBody),
        }),
        { secrets: [secret] },
      ),
    ).rejects.toMatchObject({ code: 'timestamp_skew' });
  });
});

describe('Telegram verifier', () => {
  const secret = 'telegram_webhook-token_123';

  test('compares the static token and returns update_id as native identity', async () => {
    const rawBody = body({
      update_id: 987654321,
      message: { message_id: 42, text: 'hello mercury' },
    });

    const result = await telegramVerifier.verify(
      request(rawBody, {
        'X-Telegram-Bot-Api-Secret-Token': secret,
      }),
      { secrets: ['rotating-secret', secret] },
    );

    expect(result.dedupId).toBe('987654321');
    expect(result.metadata.sequence).toBe('987654321');
  });

  test('rejects a forged token before parsing malformed JSON', async () => {
    await expect(
      telegramVerifier.verify(
        request(encoder.encode('{not-json'), {
          'X-Telegram-Bot-Api-Secret-Token': 'forged',
        }),
        { secrets: [secret] },
      ),
    ).rejects.toMatchObject({ code: 'invalid_signature' });
  });

  test('uses a stable payload plus token fallback without update_id', async () => {
    const rawBody = body({ message: { text: 'channel post' } });
    const verificationRequest = request(rawBody, {
      'X-Telegram-Bot-Api-Secret-Token': secret,
    });

    const first = await telegramVerifier.verify(verificationRequest, {
      secrets: [secret],
    });
    const retry = await telegramVerifier.verify(verificationRequest, {
      secrets: [secret],
    });

    expect(first.dedupId).toMatch(/^sha256:[\da-f]{64}$/);
    expect(retry.dedupId).toBe(first.dedupId);
  });
});

describe('Logto verifier', () => {
  const secret = 'logto-signing-key';

  test('verifies the raw-body HMAC and derives a stable fallback identity', async () => {
    const rawBody = body({
      hookId: 'hook_mercury',
      event: 'User.Data.Updated',
      createdAt: '2026-07-29T00:09:58.000Z',
      data: { id: 'user_123' },
    });
    const signature = hmac(secret, rawBody);
    const verificationRequest = request(rawBody, {
      'Logto-Signature-Sha-256': signature,
    });

    const first = await logtoVerifier.verify(verificationRequest, {
      secrets: [secret],
    });
    const retry = await logtoVerifier.verify(verificationRequest, {
      secrets: [secret],
    });

    expect(first.dedupId).toMatch(/^sha256:[\da-f]{64}$/);
    expect(retry.dedupId).toBe(first.dedupId);
    expect(first.metadata).toEqual({
      eventType: 'User.Data.Updated',
      providerTimestamp: now.getTime() - 2_000,
    });
  });

  test('rejects forged and malformed signed payloads', async () => {
    const validBody = body({ hookId: 'hook_mercury' });
    await expect(
      logtoVerifier.verify(
        request(validBody, {
          'logto-signature-sha-256': '0'.repeat(64),
        }),
        { secrets: [secret] },
      ),
    ).rejects.toMatchObject({ code: 'invalid_signature' });

    const malformedBody = encoder.encode('{not-json');
    await expect(
      logtoVerifier.verify(
        request(malformedBody, {
          'logto-signature-sha-256': hmac(secret, malformedBody),
        }),
        { secrets: [secret] },
      ),
    ).rejects.toMatchObject({ code: 'malformed_payload' });
  });
});
