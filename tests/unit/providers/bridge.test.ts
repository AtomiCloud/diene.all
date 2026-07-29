import { describe, expect, test } from 'bun:test';
import { createHmac } from 'node:crypto';
import { generateKeyPair, SignJWT } from 'jose';
import type { VerificationInput } from '../../../src/domain/index.ts';
import {
  createProviderVerifierRegistry,
  type ProviderBridgeFailure,
  type ProviderConfigurationReader,
  providerNames,
  validateProviderConfiguration,
} from '../../../src/providers/index.ts';
import { appleRootCertificate } from './apple-fixture.ts';

const encoder = new TextEncoder();
const now = new Date('2026-07-29T00:10:00.000Z');
const registeredUrl = 'https://hooks.webhook.mercury.mew.cluster.atomi.cloud/t/acme/provider';

class RecordingConfigurationReader implements ProviderConfigurationReader {
  readonly references: string[] = [];
  readonly #values: Readonly<Record<string, unknown>>;
  readonly #error: Error | undefined;

  constructor(values: Readonly<Record<string, unknown>> = {}, error?: Error) {
    this.#values = values;
    this.#error = error;
  }

  async read(reference: string): Promise<unknown | undefined> {
    this.references.push(reference);
    if (this.#error !== undefined) {
      throw this.#error;
    }
    return this.#values[reference];
  }
}

const input = (
  provider: string,
  rawBody: Uint8Array,
  headers: Readonly<Record<string, string>>,
  verificationSecretRef: string | undefined = 'verification/provider',
  url = registeredUrl,
): VerificationInput => ({
  provider,
  rawBody,
  headers,
  registeredUrl: url,
  ...(verificationSecretRef === undefined ? {} : { verificationSecretRef }),
});

const hmac = (secret: string, ...parts: readonly (string | Uint8Array)[]): string => {
  const digest = createHmac('sha256', secret);
  for (const part of parts) {
    digest.update(part);
  }
  return digest.digest('hex');
};

describe('provider runtime bridge', () => {
  test('recognizes exactly the seven v1 names and rejects unknown providers before configuration reads', async () => {
    const reader = new RecordingConfigurationReader();
    const bridge = createProviderVerifierRegistry(reader, { now: () => now });

    for (const provider of providerNames) {
      const result = await bridge.verify(input(provider, encoder.encode('{}'), {}));
      expect(await result.unwrapErr()).toMatchObject({ code: 'missing-credential' });
    }
    expect(reader.references).toHaveLength(providerNames.length);

    const unknown = await bridge.verify(input('cloudflare', encoder.encode('{}'), {}));
    expect((await unknown.unwrapErr()) as ProviderBridgeFailure).toEqual({
      code: 'unsupported-provider',
      kind: 'unsupported-provider',
      message: 'Webhook provider is not supported',
      retryable: true,
    });
    expect(reader.references).toHaveLength(providerNames.length);
  });

  test('rejects a missing pointer before any read and maps absent, malformed, and unavailable configuration', async () => {
    const reader = new RecordingConfigurationReader({
      malformed: { secrets: [] },
    });
    const bridge = createProviderVerifierRegistry(reader, { now: () => now });

    const missingPointer = await bridge.verify({
      provider: 'stripe',
      rawBody: encoder.encode('{}'),
      headers: {},
      registeredUrl,
    });
    expect(await missingPointer.unwrapErr()).toMatchObject({ code: 'missing-credential' });
    expect(reader.references).toEqual([]);

    const absent = await bridge.verify(input('stripe', encoder.encode('{}'), {}, 'absent'));
    expect(await absent.unwrapErr()).toMatchObject({ code: 'missing-credential' });

    const malformed = await bridge.verify(input('stripe', encoder.encode('{}'), {}, 'malformed'));
    expect(await malformed.unwrapErr()).toMatchObject({ code: 'missing-credential' });

    const unavailableBridge = createProviderVerifierRegistry(
      new RecordingConfigurationReader({}, new Error('vault details must not escape')),
      { now: () => now },
    );
    const unavailable = await unavailableBridge.verify(input('stripe', encoder.encode('{}'), {}, 'unavailable'));
    expect((await unavailable.unwrapErr()) as ProviderBridgeFailure).toEqual({
      code: 'missing-credential',
      kind: 'configuration-unavailable',
      message: 'Provider verification configuration is unavailable',
      retryable: true,
    });
  });

  test('preflights the exact provider set and each provider-specific credential shape', async () => {
    const { publicKey } = await generateKeyPair('RS256');
    const configurations = {
      stripe: { secrets: ['stripe-secret'] },
      airwallex: { secrets: ['airwallex-secret'] },
      'apple-app-store': {
        trustedRootCertificates: [appleRootCertificate],
        bundleId: 'cloud.atomi.mercury',
        environment: 'Production',
      },
      'google-play': {
        key: publicKey,
        serviceAccountEmail: 'push@atomi.iam.gserviceaccount.com',
      },
      telegram: { secrets: ['telegram-secret'] },
      discord: { publicKeys: ['a'.repeat(64)] },
      logto: { secrets: ['logto-secret'] },
    } satisfies Record<(typeof providerNames)[number], unknown>;

    for (const provider of providerNames) {
      expect(validateProviderConfiguration(provider, configurations[provider])).toMatchObject({
        ok: true,
        provider,
      });
    }
    expect(validateProviderConfiguration('cloudflare', { secrets: ['secret'] })).toEqual({
      ok: false,
      failure: {
        code: 'unsupported-provider',
        kind: 'unsupported-provider',
        message: 'Webhook provider is not supported',
        retryable: true,
      },
    });
    expect(validateProviderConfiguration('stripe', { secrets: [] })).toMatchObject({
      ok: false,
      failure: {
        code: 'missing-credential',
        kind: 'configuration-malformed',
        retryable: true,
      },
    });
    expect(
      validateProviderConfiguration('discord', {
        publicKeys: ['not-an-ed25519-public-key'],
      }),
    ).toMatchObject({
      ok: false,
      failure: { kind: 'configuration-malformed' },
    });
    expect(
      validateProviderConfiguration('google-play', {
        key: {},
        serviceAccountEmail: 'push@atomi.iam.gserviceaccount.com',
      }),
    ).toMatchObject({
      ok: false,
      failure: { kind: 'configuration-malformed' },
    });
    expect(
      validateProviderConfiguration('apple-app-store', {
        trustedRootCertificates: ['not-a-certificate'],
        bundleId: 'cloud.atomi.mercury',
        environment: 'Production',
      }),
    ).toMatchObject({
      ok: false,
      failure: { kind: 'configuration-malformed' },
    });
  });

  test('maps dual-live Stripe verification into native domain evidence without throwing', async () => {
    const secret = 'stripe-current-secret';
    const timestamp = Math.floor(now.getTime() / 1_000);
    const rawBody = encoder.encode(
      JSON.stringify({
        id: 'evt_bridge_native',
        type: 'invoice.paid',
        created: timestamp - 2,
      }),
    );
    const signatureHeader = `t=${timestamp},v1=${hmac(secret, `${timestamp}.`, rawBody)}`;
    const bridge = createProviderVerifierRegistry(
      new RecordingConfigurationReader({
        'verification/provider': {
          secrets: ['stripe-next-secret', secret],
        },
      }),
      { now: () => now },
    );

    const result = await bridge.verify(input('stripe', rawBody, { 'Stripe-Signature': signatureHeader }));

    expect(await result.unwrap()).toEqual({
      providerEventId: 'evt_bridge_native',
      providerTimestampMs: (timestamp - 2) * 1_000,
      signatureMaterial: signatureHeader,
      metadata: {
        provider: 'stripe',
        eventType: 'invoice.paid',
      },
    });
  });

  test('preserves sequence and fallback signature evidence', async () => {
    const token = 'telegram_static_token';
    const reader = new RecordingConfigurationReader({
      'verification/provider': { secrets: [token] },
    });
    const bridge = createProviderVerifierRegistry(reader, { now: () => now });

    const native = await bridge.verify(
      input('telegram', encoder.encode(JSON.stringify({ update_id: 441, message: { text: 'native' } })), {
        'X-Telegram-Bot-Api-Secret-Token': token,
      }),
    );
    expect(await native.unwrap()).toMatchObject({
      providerEventId: '441',
      providerSequence: '441',
      signatureMaterial: token,
    });

    const fallback = await bridge.verify(
      input('telegram', encoder.encode(JSON.stringify({ message: { text: 'fallback' } })), {
        'X-Telegram-Bot-Api-Secret-Token': token,
      }),
    );
    expect(await fallback.unwrap()).toEqual({
      signatureMaterial: token,
      metadata: { provider: 'telegram' },
    });
  });

  test('translates adapter verification failures into domain results', async () => {
    const timestamp = Math.floor(now.getTime() / 1_000);
    const bridge = createProviderVerifierRegistry(
      new RecordingConfigurationReader({
        'verification/provider': { secrets: ['stripe-secret'] },
      }),
      { now: () => now },
    );

    const result = await bridge.verify(
      input('stripe', encoder.encode(JSON.stringify({ id: 'evt_forged' })), {
        'Stripe-Signature': `t=${timestamp},v1=${'0'.repeat(64)}`,
      }),
    );

    expect((await result.unwrapErr()) as ProviderBridgeFailure).toEqual({
      code: 'invalid-signature',
      kind: 'request-authentication-rejected',
      message: 'Provider webhook authentication evidence was rejected',
      retryable: false,
    });
  });

  test('tries ordered live and overlap references while internal faults dominate a final rejection', async () => {
    const current = 'stripe-current-secret';
    const overlap = 'stripe-overlap-secret';
    const timestamp = Math.floor(now.getTime() / 1_000);
    const rawBody = encoder.encode(JSON.stringify({ id: 'evt_overlap' }));
    const rotatingInput: VerificationInput = {
      provider: 'stripe',
      rawBody,
      headers: {
        'Stripe-Signature': `t=${timestamp},v1=${hmac(overlap, `${timestamp}.`, rawBody)}`,
      },
      registeredUrl,
      verificationSecretRefs: ['current', 'overlap'],
    };
    const reader = new RecordingConfigurationReader({
      current: { secrets: [current] },
      overlap: { secrets: [overlap] },
    });
    const bridge = createProviderVerifierRegistry(reader, { now: () => now });

    expect(await (await bridge.verify(rotatingInput)).unwrap()).toMatchObject({
      providerEventId: 'evt_overlap',
    });
    expect(reader.references).toEqual(['current', 'overlap']);

    const currentReader = new RecordingConfigurationReader({
      current: { secrets: [current] },
      overlap: { secrets: [overlap] },
    });
    const currentResult = await createProviderVerifierRegistry(currentReader, { now: () => now }).verify({
      ...rotatingInput,
      headers: {
        'Stripe-Signature': `t=${timestamp},v1=${hmac(current, `${timestamp}.`, rawBody)}`,
      },
    });
    expect(await currentResult.unwrap()).toMatchObject({ providerEventId: 'evt_overlap' });
    expect(currentReader.references).toEqual(['current', 'overlap']);

    const unavailableSecret = 'vault-error-must-not-escape';
    const mixedReader: ProviderConfigurationReader = {
      read: async reference => {
        if (reference === 'current') {
          throw new Error(unavailableSecret);
        }
        return { secrets: [overlap] };
      },
    };
    const rejected = await createProviderVerifierRegistry(mixedReader, { now: () => now }).verify({
      ...rotatingInput,
      headers: {
        'Stripe-Signature': `t=${timestamp},v1=${'0'.repeat(64)}`,
      },
    });
    const failure = await rejected.unwrapErr();
    expect(failure).toMatchObject({
      code: 'missing-credential',
      kind: 'configuration-unavailable',
      retryable: true,
    });
    expect(JSON.stringify(failure)).not.toContain(unavailableSecret);
  });

  test('keeps key-resolution and unexpected verifier faults retryable without leaking causes', async () => {
    const { privateKey } = await generateKeyPair('RS256');
    const serviceAccountEmail = 'mercury-pubsub@acme.iam.gserviceaccount.com';
    const nowSeconds = Math.floor(now.getTime() / 1_000);
    const token = await new SignJWT({
      email: serviceAccountEmail,
      email_verified: true,
    })
      .setProtectedHeader({ alg: 'RS256', kid: 'remote-key' })
      .setIssuer('https://accounts.google.com')
      .setAudience(registeredUrl)
      .setIssuedAt(nowSeconds - 1)
      .setExpirationTime(nowSeconds + 300)
      .sign(privateKey);
    const remoteSecret = 'remote-jwks-secret-must-not-escape';
    const dependencyBridge = createProviderVerifierRegistry(
      new RecordingConfigurationReader({
        'verification/provider': {
          key: async () => {
            throw new Error(remoteSecret);
          },
          serviceAccountEmail,
        },
      }),
      { now: () => now },
    );
    const dependency = await dependencyBridge.verify(
      input('google-play', encoder.encode(JSON.stringify({ message: { messageId: 'dependency' } })), {
        Authorization: `Bearer ${token}`,
      }),
    );
    const dependencyFailure = await dependency.unwrapErr();
    expect(dependencyFailure).toMatchObject({
      code: 'missing-credential',
      kind: 'dependency-unavailable',
      retryable: true,
    });
    expect(JSON.stringify(dependencyFailure)).not.toContain(remoteSecret);

    let secretReads = 0;
    const unexpectedSecret = 'unexpected-verifier-secret-must-not-escape';
    const unstableConfiguration = Object.defineProperty({}, 'secrets', {
      enumerable: true,
      get: () => {
        secretReads += 1;
        if (secretReads === 1) {
          return ['stripe-secret'];
        }
        throw new Error(unexpectedSecret);
      },
    });
    const unexpectedBridge = createProviderVerifierRegistry(
      new RecordingConfigurationReader({
        'verification/provider': unstableConfiguration,
      }),
      { now: () => now },
    );
    const unexpected = await unexpectedBridge.verify(
      input('stripe', encoder.encode('{}'), {
        'Stripe-Signature': `t=${nowSeconds},v1=${'0'.repeat(64)}`,
      }),
    );
    const unexpectedFailure = await unexpected.unwrapErr();
    expect(unexpectedFailure).toMatchObject({
      code: 'missing-credential',
      kind: 'unexpected-verifier-failure',
      retryable: true,
    });
    expect(JSON.stringify(unexpectedFailure)).not.toContain(unexpectedSecret);
  });

  test('passes the stored registered URL unchanged despite hostile host headers', async () => {
    const { privateKey, publicKey } = await generateKeyPair('RS256');
    const serviceAccountEmail = 'mercury-pubsub@acme.iam.gserviceaccount.com';
    const nowSeconds = Math.floor(now.getTime() / 1_000);
    const token = await new SignJWT({
      email: serviceAccountEmail,
      email_verified: true,
    })
      .setProtectedHeader({ alg: 'RS256', kid: 'bridge-google-key' })
      .setIssuer('https://accounts.google.com')
      .setSubject('109876543210987654321')
      .setAudience(registeredUrl)
      .setIssuedAt(nowSeconds - 1)
      .setExpirationTime(nowSeconds + 300)
      .sign(privateKey);
    const reader = new RecordingConfigurationReader({
      'verification/provider': {
        key: publicKey,
        serviceAccountEmail,
      },
    });
    const bridge = createProviderVerifierRegistry(reader, { now: () => now });
    const rawBody = encoder.encode(
      JSON.stringify({
        message: {
          messageId: 'google-host-proof',
          publishTime: '2026-07-29T00:09:59.000Z',
        },
      }),
    );

    const result = await bridge.verify(
      input('google-play', rawBody, {
        Authorization: `Bearer ${token}`,
        Host: 'attacker.invalid',
        'X-Forwarded-Host': 'also-attacker.invalid',
      }),
    );

    expect(await result.unwrap()).toMatchObject({
      providerEventId: 'google-host-proof',
      providerTimestampMs: now.getTime() - 1_000,
      metadata: { provider: 'google-play' },
    });
  });
});
