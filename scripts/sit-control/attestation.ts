import { createHash, createPublicKey, verify } from 'node:crypto';
import { z } from 'zod';

const nonEmpty = z.string().min(1);
const timestamp = z.number().int().nonnegative();

const trustEntrySchema = z
  .object({
    authorityId: nonEmpty,
    keyId: nonEmpty,
    url: z.string().url(),
    resourceIdentity: nonEmpty,
    publicKeyPem: nonEmpty,
  })
  .strict();

const trustSchema = z.record(nonEmpty, trustEntrySchema);

const requestSchema = z
  .object({
    protocol: z.literal('mercury-sit-proof-request/v1'),
    scenario: nonEmpty,
    sessionId: nonEmpty,
    nonce: nonEmpty,
    productBaseUrl: z.string().url(),
    landscapes: z.array(nonEmpty).min(2),
    resourceIdentity: nonEmpty,
    requestedAtMs: timestamp,
  })
  .strict();

const attestationSchema = z
  .object({
    protocol: z.literal('mercury-sit-attestation/v1'),
    authorityId: nonEmpty,
    keyId: nonEmpty,
    scenario: nonEmpty,
    sessionId: nonEmpty,
    nonce: nonEmpty,
    resourceIdentity: nonEmpty,
    requestDigest: z.string().regex(/^[a-f0-9]{64}$/),
    issuedAtMs: timestamp,
    expiresAtMs: timestamp,
    observedOperation: z
      .object({
        id: nonEmpty,
        kind: nonEmpty,
        productBaseUrl: z.string().url(),
        resourceIdentity: nonEmpty,
        completedAtMs: timestamp,
      })
      .strict(),
    evidence: z.unknown(),
    signature: nonEmpty,
  })
  .strict();

export interface AttestationSession {
  readonly id: string;
  readonly nonce: string;
  readonly productBaseUrl: string;
}

export interface VerifyAttestationInput {
  readonly scenario: string;
  readonly session: AttestationSession;
  readonly landscapes: readonly string[];
  readonly trustJson: string | undefined;
  readonly bearer: string | undefined;
  readonly nowMs?: number;
  readonly fetcher?: typeof fetch;
}

const canonical = (value: unknown): string => {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(item => canonical(item)).join(',')}]`;
  return `{${Object.entries(value as Readonly<Record<string, unknown>>)
    .sort(([left], [right]) => (left < right ? -1 : left > right ? 1 : 0))
    .map(([key, item]) => `${JSON.stringify(key)}:${canonical(item)}`)
    .join(',')}}`;
};

export const requestDigest = (request: unknown): string =>
  createHash('sha256').update(canonical(request)).digest('hex');

export const signedAttestationPayload = (attestation: unknown): string => {
  if (attestation === null || typeof attestation !== 'object' || Array.isArray(attestation)) {
    throw new Error('attestation must be an object');
  }
  const unsigned = { ...(attestation as Readonly<Record<string, unknown>>) };
  Reflect.deleteProperty(unsigned, 'signature');
  return canonical(unsigned);
};

export const verifyAuthorityAttestation = async (input: VerifyAttestationInput): Promise<unknown> => {
  if (input.trustJson === undefined || input.trustJson.trim().length === 0) {
    throw new Error(`missing approved authority trust for ${input.scenario}`);
  }
  if (input.bearer === undefined || input.bearer.trim().length === 0) {
    throw new Error(`missing authority credential for ${input.scenario}`);
  }

  let rawTrust: unknown;
  try {
    rawTrust = JSON.parse(input.trustJson);
  } catch {
    throw new Error('MERCURY_SIT_PROOF_TRUST_JSON is not valid JSON');
  }
  const trust = trustSchema.parse(rawTrust);
  const authority = trust[input.scenario];
  if (authority === undefined) throw new Error(`no approved authority for ${input.scenario}`);
  const url = new URL(authority.url);
  if (url.protocol !== 'https:' || url.username.length > 0 || url.password.length > 0 || url.hash.length > 0) {
    throw new Error(`approved authority URL for ${input.scenario} must be an uncredentialed HTTPS URL`);
  }

  const nowMs = input.nowMs ?? Date.now();
  const request = requestSchema.parse({
    protocol: 'mercury-sit-proof-request/v1',
    scenario: input.scenario,
    sessionId: input.session.id,
    nonce: input.session.nonce,
    productBaseUrl: input.session.productBaseUrl,
    landscapes: input.landscapes,
    resourceIdentity: authority.resourceIdentity,
    requestedAtMs: nowMs,
  });
  const digest = requestDigest(request);
  const response = await (input.fetcher ?? fetch)(authority.url, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${input.bearer.trim()}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify(request),
  });
  const rawBody = await response.text();
  if (!response.ok) {
    throw new Error(`approved authority ${authority.authorityId} returned ${response.status}`);
  }
  if (!response.headers.get('content-type')?.toLowerCase().startsWith('application/json')) {
    throw new Error(`approved authority ${authority.authorityId} did not return JSON`);
  }

  let rawAttestation: unknown;
  try {
    rawAttestation = JSON.parse(rawBody);
  } catch {
    throw new Error(`approved authority ${authority.authorityId} returned malformed JSON`);
  }
  const attestation = attestationSchema.parse(rawAttestation);
  if (
    attestation.authorityId !== authority.authorityId ||
    attestation.keyId !== authority.keyId ||
    attestation.scenario !== input.scenario ||
    attestation.sessionId !== input.session.id ||
    attestation.nonce !== input.session.nonce ||
    attestation.resourceIdentity !== authority.resourceIdentity ||
    attestation.requestDigest !== digest ||
    attestation.observedOperation.productBaseUrl !== input.session.productBaseUrl ||
    attestation.observedOperation.resourceIdentity !== authority.resourceIdentity
  ) {
    throw new Error(`approved authority ${authority.authorityId} returned an unbound attestation`);
  }
  if (
    attestation.issuedAtMs < nowMs - 60_000 ||
    attestation.issuedAtMs > nowMs + 5_000 ||
    attestation.expiresAtMs <= nowMs ||
    attestation.expiresAtMs > attestation.issuedAtMs + 300_000 ||
    attestation.observedOperation.completedAtMs < request.requestedAtMs ||
    attestation.observedOperation.completedAtMs > attestation.issuedAtMs
  ) {
    throw new Error(`approved authority ${authority.authorityId} returned a stale attestation`);
  }

  const publicKey = createPublicKey(authority.publicKeyPem);
  if (publicKey.asymmetricKeyType !== 'ed25519') {
    throw new Error(`approved authority ${authority.authorityId} must use Ed25519`);
  }
  const signature = Buffer.from(attestation.signature, 'base64url');
  if (!verify(null, Buffer.from(signedAttestationPayload(attestation)), publicKey, signature)) {
    throw new Error(`approved authority ${authority.authorityId} signature is invalid`);
  }
  return attestation.evidence;
};
