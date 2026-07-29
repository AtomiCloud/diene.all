import { describe, expect, it } from 'bun:test';
import { generateKeyPairSync, sign } from 'node:crypto';
import {
  requestDigest,
  signedAttestationPayload,
  verifyAuthorityAttestation,
} from '../../scripts/sit-control/attestation.ts';

const nowMs = 1_800_000_000_000;
const session = {
  id: 'session-one',
  nonce: 'nonce-one',
  productBaseUrl: 'https://127.0.0.1:8443',
};
const authorityUrl = 'https://proof.example.test/v1/observe';
const resourceIdentity = 'route53:Z123:hooks.webhook.mercury.example';
const { privateKey, publicKey } = generateKeyPairSync('ed25519');
const trustJson = JSON.stringify({
  'route53-landing': {
    authorityId: 'platform-dns',
    keyId: 'dns-2026-07',
    url: authorityUrl,
    resourceIdentity,
    publicKeyPem: publicKey.export({ format: 'pem', type: 'spki' }).toString(),
  },
});

const fetcherFor = (mutate: (value: Record<string, unknown>) => void = () => undefined): typeof fetch =>
  (async (_url: string | URL | Request, init?: RequestInit) => {
    const request = JSON.parse(String(init?.body)) as Record<string, unknown>;
    const attestation: Record<string, unknown> = {
      protocol: 'mercury-sit-attestation/v1',
      authorityId: 'platform-dns',
      keyId: 'dns-2026-07',
      scenario: 'route53-landing',
      sessionId: session.id,
      nonce: session.nonce,
      resourceIdentity,
      requestDigest: requestDigest(request),
      issuedAtMs: nowMs + 100,
      expiresAtMs: nowMs + 60_000,
      observedOperation: {
        id: 'route53-change-C123',
        kind: 'route53.get-resource-record-sets-and-product-probe',
        productBaseUrl: session.productBaseUrl,
        resourceIdentity,
        completedAtMs: nowMs + 50,
      },
      evidence: { providerResponseStatus: 200 },
    };
    mutate(attestation);
    attestation.signature = sign(null, Buffer.from(signedAttestationPayload(attestation)), privateKey).toString(
      'base64url',
    );
    return Response.json(attestation);
  }) as typeof fetch;

describe('approved SIT authority attestations', () => {
  it('accepts a fresh signature bound to the exact run, request, product, and resource', async () => {
    await expect(
      verifyAuthorityAttestation({
        scenario: 'route53-landing',
        session,
        landscapes: ['lapras', 'farfetch'],
        trustJson,
        bearer: 'authority-token',
        nowMs,
        fetcher: fetcherFor(),
      }),
    ).resolves.toEqual({ providerResponseStatus: 200 });
  });

  for (const [name, mutate] of [
    ['nonce', (value: Record<string, unknown>) => (value.nonce = 'another-run')],
    ['resource', (value: Record<string, unknown>) => (value.resourceIdentity = 'route53:another-zone')],
    ['digest', (value: Record<string, unknown>) => (value.requestDigest = '0'.repeat(64))],
    ['expiry', (value: Record<string, unknown>) => (value.expiresAtMs = nowMs)],
  ] as const) {
    it(`rejects a schema-valid success with a mismatched ${name}`, async () => {
      await expect(
        verifyAuthorityAttestation({
          scenario: 'route53-landing',
          session,
          landscapes: ['lapras', 'farfetch'],
          trustJson,
          bearer: 'authority-token',
          nowMs,
          fetcher: fetcherFor(mutate),
        }),
      ).rejects.toThrow();
    });
  }

  it('rejects an arbitrary URL trust entry before making a request', async () => {
    await expect(
      verifyAuthorityAttestation({
        scenario: 'route53-landing',
        session,
        landscapes: ['lapras', 'farfetch'],
        trustJson: trustJson.replace('https://proof.example.test', 'http://127.0.0.1'),
        bearer: 'authority-token',
        nowMs,
        fetcher: fetcherFor(),
      }),
    ).rejects.toThrow('HTTPS');
  });

  it('rejects schema-valid evidence carrying an untrusted signature', async () => {
    const { privateKey: wrongKey } = generateKeyPairSync('ed25519');
    const wrongSigner = (async (_url: string | URL | Request, init?: RequestInit) => {
      const request = JSON.parse(String(init?.body)) as Record<string, unknown>;
      const attestation: Record<string, unknown> = {
        protocol: 'mercury-sit-attestation/v1',
        authorityId: 'platform-dns',
        keyId: 'dns-2026-07',
        scenario: 'route53-landing',
        sessionId: session.id,
        nonce: session.nonce,
        resourceIdentity,
        requestDigest: requestDigest(request),
        issuedAtMs: nowMs + 100,
        expiresAtMs: nowMs + 60_000,
        observedOperation: {
          id: 'route53-change-forged',
          kind: 'route53.get-resource-record-sets-and-product-probe',
          productBaseUrl: session.productBaseUrl,
          resourceIdentity,
          completedAtMs: nowMs + 50,
        },
        evidence: { providerResponseStatus: 200 },
      };
      attestation.signature = sign(null, Buffer.from(signedAttestationPayload(attestation)), wrongKey).toString(
        'base64url',
      );
      return Response.json(attestation);
    }) as typeof fetch;

    await expect(
      verifyAuthorityAttestation({
        scenario: 'route53-landing',
        session,
        landscapes: ['lapras', 'farfetch'],
        trustJson,
        bearer: 'authority-token',
        nowMs,
        fetcher: wrongSigner,
      }),
    ).rejects.toThrow('signature is invalid');
  });
});
