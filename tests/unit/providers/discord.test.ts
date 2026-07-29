import { describe, expect, test } from 'bun:test';
import { getPublicKeyAsync, signAsync, utils } from '@noble/ed25519';
import { discordVerifier, type VerificationRequest } from '../../../src/providers/index.ts';

const encoder = new TextEncoder();
const now = new Date('2026-07-29T00:10:00.000Z');

const keyMaterial = (async () => {
  const secretKey = utils.randomSecretKey();
  return {
    secretKey,
    publicKey: await getPublicKeyAsync(secretKey),
  };
})();

const signedMessage = (timestamp: string, rawBody: Uint8Array): Uint8Array => {
  const timestampBytes = encoder.encode(timestamp);
  const message = new Uint8Array(timestampBytes.length + rawBody.length);
  message.set(timestampBytes);
  message.set(rawBody, timestampBytes.length);
  return message;
};

const signedRequest = async (
  payload: unknown,
  timestamp = String(Math.floor(now.getTime() / 1_000)),
): Promise<{
  request: VerificationRequest;
  publicKeyHex: string;
}> => {
  const rawBody = encoder.encode(JSON.stringify(payload));
  const { publicKey, secretKey } = await keyMaterial;
  const signature = await signAsync(signedMessage(timestamp, rawBody), secretKey);
  return {
    request: {
      rawBody,
      headers: {
        'X-Signature-Ed25519': Buffer.from(signature).toString('hex'),
        'X-Signature-Timestamp': timestamp,
      },
      registeredUrl: 'https://hooks.webhook.mercury.mew.cluster.atomi.cloud/t/acme/discord',
      receivedAt: now,
    },
    publicKeyHex: Buffer.from(publicKey).toString('hex'),
  };
};

describe('Discord verifier', () => {
  test('verifies Ed25519(timestamp + raw body) and returns the interaction ID', async () => {
    const fixture = await signedRequest({
      id: '1137756282968739860',
      application_id: '1137756282968739859',
      type: 2,
      data: { name: 'ping' },
    });

    const result = await discordVerifier.verify(fixture.request, {
      publicKeys: ['00'.repeat(32), fixture.publicKeyHex],
      toleranceSeconds: 300,
    });

    expect(result).toMatchObject({
      provider: 'discord',
      dedupId: '1137756282968739860',
      metadata: {
        eventId: '1137756282968739860',
        providerTimestamp: now.getTime(),
      },
    });
  });

  test('rejects a forged body', async () => {
    const fixture = await signedRequest({
      id: '1137756282968739861',
      type: 1,
    });
    const forgedRequest = {
      ...fixture.request,
      rawBody: encoder.encode(JSON.stringify({ id: '1137756282968739861', type: 2 })),
    };

    await expect(
      discordVerifier.verify(forgedRequest, {
        publicKeys: [fixture.publicKeyHex],
      }),
    ).rejects.toMatchObject({ code: 'invalid_signature' });
  });

  test('rejects malformed signatures', async () => {
    const fixture = await signedRequest({ id: 'interaction_bad_signature' });

    await expect(
      discordVerifier.verify(
        {
          ...fixture.request,
          headers: {
            ...fixture.request.headers,
            'X-Signature-Ed25519': 'not-hex',
          },
        },
        { publicKeys: [fixture.publicKeyHex] },
      ),
    ).rejects.toMatchObject({ code: 'malformed_header' });
  });

  test('enforces timestamp skew when a route configures a tolerance', async () => {
    const staleTimestamp = String(Math.floor(now.getTime() / 1_000) - 301);
    const fixture = await signedRequest({ id: 'interaction_stale' }, staleTimestamp);

    await expect(
      discordVerifier.verify(fixture.request, {
        publicKeys: [fixture.publicKeyHex],
        toleranceSeconds: 300,
      }),
    ).rejects.toMatchObject({ code: 'timestamp_skew' });
  });
});
