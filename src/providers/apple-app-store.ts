import { timingSafeEqual, X509Certificate } from 'node:crypto';
import { compactVerify, decodeProtectedHeader } from 'jose';
import { currentTime, numberField, parseJson, stringField, verifiedWebhook } from './shared.ts';
import type { ProviderVerifier, VerificationRequest, VerifiedWebhook } from './types.ts';
import { VerificationError } from './types.ts';

type AppleEnvironment = 'Production' | 'Sandbox';

export interface AppleAppStoreConfiguration {
  readonly trustedRootCertificates: readonly (string | Uint8Array)[];
  readonly bundleId: string;
  readonly environment: AppleEnvironment;
  readonly appAppleId?: number;
}

const certificateFromX5c = (encoded: string): X509Certificate => {
  if (encoded.length === 0 || encoded.length % 4 !== 0 || !/^[A-Za-z\d+/]+={0,2}$/.test(encoded)) {
    throw new VerificationError('invalid_certificate', 'Apple x5c certificate is malformed');
  }
  try {
    return new X509Certificate(Buffer.from(encoded, 'base64'));
  } catch (error) {
    throw new VerificationError('invalid_certificate', 'Apple x5c certificate is malformed', { cause: error });
  }
};

const configuredCertificate = (value: string | Uint8Array): X509Certificate => {
  try {
    return new X509Certificate(value);
  } catch (error) {
    throw new VerificationError('invalid_configuration', 'Configured Apple root certificate is malformed', {
      cause: error,
    });
  }
};

const sameCertificate = (left: X509Certificate, right: X509Certificate): boolean =>
  left.raw.length === right.raw.length && timingSafeEqual(left.raw, right.raw);

const assertCertificateTime = (certificate: X509Certificate, now: Date): void => {
  const validFrom = Date.parse(certificate.validFrom);
  const validTo = Date.parse(certificate.validTo);
  if (
    !Number.isFinite(validFrom) ||
    !Number.isFinite(validTo) ||
    now.getTime() < validFrom ||
    now.getTime() > validTo
  ) {
    throw new VerificationError('invalid_certificate', 'Apple signing certificate is outside its validity period');
  }
};

const verifyCertificateChain = (
  encodedChain: readonly string[],
  trustedRoots: readonly (string | Uint8Array)[],
  now: Date,
): X509Certificate => {
  if (encodedChain.length < 2 || trustedRoots.length === 0) {
    throw new VerificationError('invalid_certificate', 'Apple x5c chain cannot reach a configured root');
  }

  const chain = encodedChain.map(certificateFromX5c);
  for (const certificate of chain) {
    assertCertificateTime(certificate, now);
  }

  for (let index = 0; index < chain.length - 1; index += 1) {
    const certificate = chain[index];
    const issuer = chain[index + 1];
    if (
      certificate === undefined ||
      issuer === undefined ||
      certificate.issuer !== issuer.subject ||
      !issuer.ca ||
      !certificate.verify(issuer.publicKey)
    ) {
      throw new VerificationError('invalid_certificate', 'Apple x5c chain signature is invalid');
    }
  }

  const root = chain.at(-1);
  const leaf = chain[0];
  if (root === undefined || leaf === undefined) {
    throw new VerificationError('invalid_certificate', 'Apple x5c chain is empty');
  }
  const anchors = trustedRoots.map(configuredCertificate);
  if (!anchors.some(anchor => sameCertificate(root, anchor))) {
    throw new VerificationError('invalid_certificate', 'Apple x5c root is not trusted');
  }

  if (
    leaf.ca ||
    leaf.publicKey.asymmetricKeyType !== 'ec' ||
    leaf.publicKey.asymmetricKeyDetails?.namedCurve !== 'prime256v1'
  ) {
    throw new VerificationError('invalid_certificate', 'Apple leaf certificate is not an ES256 signing certificate');
  }
  return leaf;
};

const verifyAppleAppStore = async (
  request: VerificationRequest,
  configuration: AppleAppStoreConfiguration,
): Promise<VerifiedWebhook> => {
  if (configuration.bundleId.length === 0) {
    throw new VerificationError('invalid_configuration', 'Apple bundle ID is required');
  }

  const envelope = parseJson(request.rawBody);
  const signedPayload = stringField(envelope, 'signedPayload');
  if (signedPayload === undefined) {
    throw new VerificationError('malformed_payload', 'Apple signedPayload is missing');
  }

  let protectedHeader: ReturnType<typeof decodeProtectedHeader>;
  try {
    protectedHeader = decodeProtectedHeader(signedPayload);
  } catch (error) {
    throw new VerificationError('malformed_payload', 'Apple signedPayload is not a compact JWS', { cause: error });
  }
  if (protectedHeader.alg !== 'ES256') {
    throw new VerificationError('unsupported_algorithm', 'Apple signedPayload must use ES256');
  }
  if (!Array.isArray(protectedHeader.x5c) || protectedHeader.x5c.some(certificate => typeof certificate !== 'string')) {
    throw new VerificationError('invalid_certificate', 'Apple signedPayload does not contain an x5c chain');
  }

  const leaf = verifyCertificateChain(
    protectedHeader.x5c as string[],
    configuration.trustedRootCertificates,
    currentTime(request.receivedAt),
  );

  let payloadBytes: Uint8Array;
  try {
    payloadBytes = (
      await compactVerify(signedPayload, leaf.publicKey, {
        algorithms: ['ES256'],
      })
    ).payload;
  } catch (error) {
    throw new VerificationError('invalid_signature', 'Apple signedPayload signature is invalid', { cause: error });
  }

  const payload = parseJson(payloadBytes);
  const data = payload.data;
  if (data === null || typeof data !== 'object' || Array.isArray(data)) {
    throw new VerificationError('malformed_payload', 'Apple notification data is missing');
  }
  const dataRecord = data as Record<string, unknown>;
  const appAppleId = numberField(dataRecord, 'appAppleId');
  if (
    stringField(dataRecord, 'bundleId') !== configuration.bundleId ||
    stringField(dataRecord, 'environment') !== configuration.environment ||
    (configuration.appAppleId !== undefined && appAppleId !== configuration.appAppleId)
  ) {
    throw new VerificationError('wrong_target', 'Apple notification is for a different app or environment');
  }

  return verifiedWebhook('apple-app-store', request.rawBody, signedPayload, {
    eventId: stringField(payload, 'notificationUUID'),
    eventType: stringField(payload, 'notificationType'),
    providerTimestamp: numberField(payload, 'signedDate'),
  });
};

export const appleAppStoreVerifier: ProviderVerifier<AppleAppStoreConfiguration> = {
  provider: 'apple-app-store',
  verify: verifyAppleAppStore,
};
