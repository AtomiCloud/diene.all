import { describe, expect, test } from 'bun:test';
import { generateKeyPair, SignJWT } from 'jose';
import { googlePlayVerifier, type VerificationRequest } from '../../../src/providers/index.ts';

const encoder = new TextEncoder();
const now = new Date('2026-07-29T00:10:00.000Z');
const nowSeconds = Math.floor(now.getTime() / 1_000);
const registeredUrl = 'https://hooks.webhook.mercury.mew.cluster.atomi.cloud/t/acme/google-play';
const serviceAccountEmail = 'mercury-pubsub@acme-payments.iam.gserviceaccount.com';
const keyPair = generateKeyPair('RS256');

interface TokenOptions {
  readonly audience?: string;
  readonly email?: string;
  readonly emailVerified?: boolean;
  readonly expiresAt?: number;
  readonly privateKey?: CryptoKey;
}

const oidcToken = async (options: TokenOptions = {}): Promise<string> => {
  const defaultKeyPair = await keyPair;
  return new SignJWT({
    email: options.email ?? serviceAccountEmail,
    email_verified: options.emailVerified ?? true,
  })
    .setProtectedHeader({ alg: 'RS256', kid: 'google-test-key' })
    .setIssuer('https://accounts.google.com')
    .setSubject('109876543210987654321')
    .setAudience(options.audience ?? registeredUrl)
    .setIssuedAt(nowSeconds - 1)
    .setExpirationTime(options.expiresAt ?? nowSeconds + 300)
    .sign(options.privateKey ?? defaultKeyPair.privateKey);
};

const request = (rawBody: Uint8Array, token: string, url = registeredUrl): VerificationRequest => ({
  rawBody,
  headers: { Authorization: `Bearer ${token}` },
  registeredUrl: url,
  receivedAt: now,
});

describe('Google Play RTDN verifier', () => {
  test('verifies Pub/Sub OIDC claims and returns the Pub/Sub message ID', async () => {
    const { publicKey } = await keyPair;
    const token = await oidcToken();
    const rawBody = encoder.encode(
      JSON.stringify({
        message: {
          attributes: { packageName: 'cloud.atomi.acme' },
          data: Buffer.from(
            JSON.stringify({
              version: '1.0',
              packageName: 'cloud.atomi.acme',
              eventTimeMillis: String(now.getTime() - 1_000),
              subscriptionNotification: {
                version: '1.0',
                notificationType: 2,
                purchaseToken: 'purchase-token',
                subscriptionId: 'monthly',
              },
            }),
          ).toString('base64'),
          messageId: '1215011316659232',
          publishTime: '2026-07-29T00:09:59.500Z',
        },
        subscription: 'projects/acme-payments/subscriptions/mercury-google-rtdn',
      }),
    );

    const result = await googlePlayVerifier.verify(request(rawBody, token), {
      key: publicKey,
      serviceAccountEmail,
    });

    expect(result).toMatchObject({
      provider: 'google-play',
      dedupId: '1215011316659232',
      metadata: {
        eventId: '1215011316659232',
        providerTimestamp: now.getTime() - 500,
      },
    });
  });

  test('uses the stored registered URL as the default audience', async () => {
    const { publicKey } = await keyPair;
    const token = await oidcToken();
    const rawBody = encoder.encode(JSON.stringify({ message: { messageId: 'wrong-url' } }));

    await expect(
      googlePlayVerifier.verify(request(rawBody, token, 'https://attacker.invalid/t/acme/google-play'), {
        key: publicKey,
        serviceAccountEmail,
      }),
    ).rejects.toMatchObject({ code: 'invalid_signature' });
  });

  test('rejects expired tokens and wrong service-account claims', async () => {
    const { publicKey } = await keyPair;
    const rawBody = encoder.encode(JSON.stringify({ message: { messageId: 'claims' } }));
    const expired = await oidcToken({ expiresAt: nowSeconds - 1 });

    await expect(
      googlePlayVerifier.verify(request(rawBody, expired), {
        key: publicKey,
        serviceAccountEmail,
      }),
    ).rejects.toMatchObject({ code: 'invalid_signature' });

    const wrongEmail = await oidcToken({
      email: 'attacker@example.com',
    });
    await expect(
      googlePlayVerifier.verify(request(rawBody, wrongEmail), {
        key: publicKey,
        serviceAccountEmail,
      }),
    ).rejects.toMatchObject({ code: 'invalid_claims' });
  });

  test('rejects tokens signed by a forged key', async () => {
    const { publicKey } = await keyPair;
    const forgedKeys = await generateKeyPair('RS256');
    const forged = await oidcToken({ privateKey: forgedKeys.privateKey });
    const rawBody = encoder.encode(JSON.stringify({ message: { messageId: 'forged' } }));

    await expect(
      googlePlayVerifier.verify(request(rawBody, forged), {
        key: publicKey,
        serviceAccountEmail,
      }),
    ).rejects.toMatchObject({ code: 'invalid_signature' });
  });

  test('authenticates before rejecting malformed Pub/Sub JSON', async () => {
    const { publicKey } = await keyPair;
    const malformedBody = encoder.encode('{not-json');

    await expect(
      googlePlayVerifier.verify(request(malformedBody, await oidcToken()), { key: publicKey, serviceAccountEmail }),
    ).rejects.toMatchObject({ code: 'malformed_payload' });
  });
});
