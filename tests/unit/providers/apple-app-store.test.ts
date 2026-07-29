import { describe, expect, test } from 'bun:test';
import { createPrivateKey, X509Certificate } from 'node:crypto';
import { CompactSign } from 'jose';
import { appleAppStoreVerifier, type VerificationRequest } from '../../../src/providers/index.ts';
import {
  appleIntermediateCertificate,
  appleLeafCertificate,
  appleLeafPkcs8DerBase64,
  appleRootCertificate,
} from './apple-fixture.ts';

const encoder = new TextEncoder();
const now = new Date('2026-07-29T00:10:00.000Z');
const registeredUrl = 'https://hooks.webhook.mercury.mew.cluster.atomi.cloud/t/acme/apple';

const x5c = [
  new X509Certificate(appleLeafCertificate).raw.toString('base64'),
  new X509Certificate(appleIntermediateCertificate).raw.toString('base64'),
  new X509Certificate(appleRootCertificate).raw.toString('base64'),
];

const signedPayload = async (overrides: Readonly<Record<string, unknown>> = {}): Promise<string> => {
  const key = createPrivateKey({
    key: Buffer.from(appleLeafPkcs8DerBase64, 'base64'),
    format: 'der',
    type: 'pkcs8',
  });
  const payload = {
    notificationType: 'DID_RENEW',
    subtype: 'BILLING_RECOVERY',
    notificationUUID: 'cb4e0c3b-5be7-4f79-8a7b-6908ccfc33f4',
    version: '2.0',
    signedDate: now.getTime() - 1_000,
    data: {
      appAppleId: 1234567890,
      bundleId: 'cloud.atomi.acme',
      environment: 'Sandbox',
    },
    ...overrides,
  };

  return new CompactSign(encoder.encode(JSON.stringify(payload))).setProtectedHeader({ alg: 'ES256', x5c }).sign(key);
};

const request = (payload: string, receivedAt = now): VerificationRequest => ({
  rawBody: encoder.encode(JSON.stringify({ signedPayload: payload })),
  headers: {},
  registeredUrl,
  receivedAt,
});

const configuration = {
  trustedRootCertificates: [appleRootCertificate],
  bundleId: 'cloud.atomi.acme',
  environment: 'Sandbox' as const,
  appAppleId: 1234567890,
};

describe('Apple App Store Server Notifications v2 verifier', () => {
  test('validates ES256 JWS and the complete x5c trust chain', async () => {
    const result = await appleAppStoreVerifier.verify(request(await signedPayload()), configuration);

    expect(result).toMatchObject({
      provider: 'apple-app-store',
      dedupId: 'cb4e0c3b-5be7-4f79-8a7b-6908ccfc33f4',
      metadata: {
        eventId: 'cb4e0c3b-5be7-4f79-8a7b-6908ccfc33f4',
        eventType: 'DID_RENEW',
        providerTimestamp: now.getTime() - 1_000,
      },
    });
  });

  test('rejects a forged JWS signature', async () => {
    const valid = await signedPayload();
    const segments = valid.split('.');
    const signature = segments[2];
    if (signature === undefined) {
      throw new Error('Test fixture did not produce a compact JWS');
    }
    segments[2] = `${signature[0] === 'A' ? 'B' : 'A'}${signature.slice(1)}`;

    await expect(appleAppStoreVerifier.verify(request(segments.join('.')), configuration)).rejects.toMatchObject({
      code: 'invalid_signature',
    });
  });

  test('rejects malformed JWS and an untrusted x5c root', async () => {
    await expect(appleAppStoreVerifier.verify(request('not-a-compact-jws'), configuration)).rejects.toMatchObject({
      code: 'malformed_payload',
    });

    await expect(
      appleAppStoreVerifier.verify(request(await signedPayload()), {
        ...configuration,
        trustedRootCertificates: [appleIntermediateCertificate],
      }),
    ).rejects.toMatchObject({ code: 'invalid_certificate' });
  });

  test('rejects certificates outside their validity period', async () => {
    await expect(
      appleAppStoreVerifier.verify(request(await signedPayload(), new Date('2040-01-01T00:00:00.000Z')), configuration),
    ).rejects.toMatchObject({ code: 'invalid_certificate' });
  });

  test('rejects notifications targeting a different app or environment', async () => {
    await expect(
      appleAppStoreVerifier.verify(request(await signedPayload()), {
        ...configuration,
        bundleId: 'cloud.atomi.attacker',
      }),
    ).rejects.toMatchObject({ code: 'wrong_target' });

    await expect(
      appleAppStoreVerifier.verify(
        request(
          await signedPayload({
            data: {
              appAppleId: 1234567890,
              bundleId: 'cloud.atomi.acme',
              environment: 'Production',
            },
          }),
        ),
        configuration,
      ),
    ).rejects.toMatchObject({ code: 'wrong_target' });
  });
});
