import { createPublicKey, KeyObject, X509Certificate } from 'node:crypto';
import { Err, Ok, type Result } from '@atomicloud/diene.result';
import type {
  ProviderVerifierRegistry,
  VerificationEvidence,
  VerificationFailure,
  VerificationInput,
} from '../domain/index.ts';
import { type AirwallexConfiguration, airwallexVerifier } from './airwallex.ts';
import { type AppleAppStoreConfiguration, appleAppStoreVerifier } from './apple-app-store.ts';
import { type DiscordConfiguration, discordVerifier } from './discord.ts';
import { type GooglePlayConfiguration, googlePlayVerifier } from './google-play.ts';
import { type LogtoConfiguration, logtoVerifier } from './logto.ts';
import { isProviderName, type ProviderConfigurations } from './registry.ts';
import { type StripeConfiguration, stripeVerifier } from './stripe.ts';
import { type TelegramConfiguration, telegramVerifier } from './telegram.ts';
import type { ProviderName, VerificationRequest, VerifiedWebhook } from './types.ts';
import { VerificationDependencyError, VerificationError } from './types.ts';

export interface ProviderConfigurationReader {
  read(reference: string): Promise<unknown | undefined>;
}

export interface ProviderVerifierRegistryOptions {
  readonly now?: () => Date;
}

type ProviderBridgeFailureKind =
  | 'request-authentication-rejected'
  | 'configuration-reference-missing'
  | 'configuration-reference-invalid'
  | 'configuration-missing'
  | 'configuration-unavailable'
  | 'configuration-malformed'
  | 'configuration-invalid'
  | 'unsupported-provider'
  | 'dependency-unavailable'
  | 'unexpected-verifier-failure';

export interface ProviderBridgeFailure extends VerificationFailure {
  readonly kind: ProviderBridgeFailureKind;
  readonly retryable: boolean;
}

export type ProviderConfigurationValidation =
  | {
      readonly ok: true;
      readonly provider: ProviderName;
      readonly configuration: ProviderConfigurations[ProviderName];
    }
  | {
      readonly ok: false;
      readonly failure: ProviderBridgeFailure;
    };

const internalFailure = (
  kind: Exclude<ProviderBridgeFailureKind, 'request-authentication-rejected' | 'unsupported-provider'>,
  message: string,
): ProviderBridgeFailure => ({
  code: 'missing-credential',
  kind,
  message,
  retryable: true,
});

const unsupportedProvider = (): ProviderBridgeFailure => ({
  code: 'unsupported-provider',
  kind: 'unsupported-provider',
  message: 'Webhook provider is not supported',
  retryable: true,
});

const invalidSignature = (): ProviderBridgeFailure => ({
  code: 'invalid-signature',
  kind: 'request-authentication-rejected',
  message: 'Provider webhook authentication evidence was rejected',
  retryable: false,
});

const isRecord = (value: unknown): value is Readonly<Record<string, unknown>> =>
  value !== null && typeof value === 'object' && !Array.isArray(value);

const hasNonEmptyStrings = (value: unknown): value is readonly string[] =>
  Array.isArray(value) && value.length > 0 && value.every(item => typeof item === 'string' && item.length > 0);

const hasValidTolerance = (value: Readonly<Record<string, unknown>>): boolean =>
  value.toleranceSeconds === undefined ||
  (typeof value.toleranceSeconds === 'number' &&
    Number.isFinite(value.toleranceSeconds) &&
    value.toleranceSeconds >= 0);

const BUNDLE_ID = /^[A-Za-z0-9][A-Za-z0-9.-]{1,254}$/u;
const GOOGLE_SERVICE_ACCOUNT_EMAIL = /^[A-Za-z0-9][A-Za-z0-9._-]{0,126}@[A-Za-z0-9.-]+\.gserviceaccount\.com$/u;

const isSecretConfiguration = (
  value: unknown,
): value is StripeConfiguration | AirwallexConfiguration | TelegramConfiguration | LogtoConfiguration =>
  isRecord(value) && hasNonEmptyStrings(value.secrets) && hasValidTolerance(value);

const isDiscordConfiguration = (value: unknown): value is DiscordConfiguration =>
  isRecord(value) &&
  hasNonEmptyStrings(value.publicKeys) &&
  value.publicKeys.every(publicKey => /^[\da-f]{64}$/iu.test(publicKey)) &&
  hasValidTolerance(value);

const isCertificateAuthority = (value: string | Uint8Array): boolean => {
  try {
    return new X509Certificate(value).ca;
  } catch {
    return false;
  }
};

const isAppleConfiguration = (value: unknown): value is AppleAppStoreConfiguration =>
  isRecord(value) &&
  Array.isArray(value.trustedRootCertificates) &&
  value.trustedRootCertificates.length > 0 &&
  value.trustedRootCertificates.every(
    certificate =>
      (typeof certificate === 'string' || certificate instanceof Uint8Array) && isCertificateAuthority(certificate),
  ) &&
  typeof value.bundleId === 'string' &&
  BUNDLE_ID.test(value.bundleId) &&
  value.bundleId.includes('.') &&
  !value.bundleId.includes('..') &&
  (value.environment === 'Production' || value.environment === 'Sandbox') &&
  (value.appAppleId === undefined ||
    (typeof value.appAppleId === 'number' && Number.isSafeInteger(value.appAppleId) && value.appAppleId >= 0));

const isRsaKeyObject = (value: unknown): value is KeyObject =>
  value instanceof KeyObject && value.type !== 'secret' && value.asymmetricKeyType === 'rsa';

const isRsaCryptoKey = (value: unknown): value is CryptoKey =>
  typeof CryptoKey !== 'undefined' &&
  value instanceof CryptoKey &&
  value.type !== 'secret' &&
  value.algorithm.name === 'RSASSA-PKCS1-v1_5';

const isRsaJwk = (value: unknown): boolean =>
  isRecord(value) &&
  value.kty === 'RSA' &&
  typeof value.n === 'string' &&
  /^[A-Za-z0-9_-]+$/u.test(value.n) &&
  typeof value.e === 'string' &&
  /^[A-Za-z0-9_-]+$/u.test(value.e) &&
  (value.alg === undefined || value.alg === 'RS256') &&
  (value.use === undefined || value.use === 'sig') &&
  (value.key_ops === undefined || (Array.isArray(value.key_ops) && value.key_ops.includes('verify')));

const isRsaPublicKeyBytes = (value: Uint8Array): boolean => {
  try {
    return isRsaKeyObject(createPublicKey(value));
  } catch {
    try {
      return isRsaKeyObject(
        createPublicKey({
          key: value,
          format: 'der',
          type: 'spki',
        }),
      );
    } catch {
      return false;
    }
  }
};

const isGoogleVerificationKey = (value: unknown): boolean =>
  typeof value === 'function' ||
  isRsaKeyObject(value) ||
  isRsaCryptoKey(value) ||
  isRsaJwk(value) ||
  (value instanceof Uint8Array && isRsaPublicKeyBytes(value));

const isGoogleConfiguration = (value: unknown): value is GooglePlayConfiguration =>
  isRecord(value) &&
  isGoogleVerificationKey(value.key) &&
  typeof value.serviceAccountEmail === 'string' &&
  GOOGLE_SERVICE_ACCOUNT_EMAIL.test(value.serviceAccountEmail) &&
  (value.audience === undefined || (typeof value.audience === 'string' && value.audience.length > 0));

const isConfiguration = <Provider extends ProviderName>(
  provider: Provider,
  value: unknown,
): value is ProviderConfigurations[Provider] => {
  switch (provider) {
    case 'stripe':
    case 'airwallex':
    case 'telegram':
    case 'logto':
      return isSecretConfiguration(value);
    case 'apple-app-store':
      return isAppleConfiguration(value);
    case 'google-play':
      return isGoogleConfiguration(value);
    case 'discord':
      return isDiscordConfiguration(value);
  }
};

/**
 * Preflights both the exact v1 provider identifier and its provider-specific
 * verifier configuration. Callers should run this before activating every
 * generated runtime configuration.
 */
export const validateProviderConfiguration = (
  provider: string,
  configuration: unknown,
): ProviderConfigurationValidation => {
  if (!isProviderName(provider)) {
    return {
      ok: false,
      failure: unsupportedProvider(),
    };
  }
  if (configuration === undefined || configuration === null) {
    return {
      ok: false,
      failure: internalFailure('configuration-missing', 'Provider verification configuration is missing'),
    };
  }
  if (!isConfiguration(provider, configuration)) {
    return {
      ok: false,
      failure: internalFailure('configuration-malformed', 'Provider verification configuration is malformed'),
    };
  }
  return {
    ok: true,
    provider,
    configuration,
  };
};

const evidenceFrom = (verified: VerifiedWebhook): VerificationEvidence => ({
  ...(verified.metadata.eventId === undefined ? {} : { providerEventId: verified.metadata.eventId }),
  ...(verified.metadata.providerTimestamp === undefined
    ? {}
    : { providerTimestampMs: verified.metadata.providerTimestamp }),
  ...(verified.metadata.sequence === undefined ? {} : { providerSequence: verified.metadata.sequence }),
  signatureMaterial: verified.signatureMaterial,
  metadata: {
    provider: verified.provider,
    ...(verified.metadata.eventType === undefined ? {} : { eventType: verified.metadata.eventType }),
  },
});

type VerificationReferenceValidation =
  | {
      readonly ok: true;
      readonly references: readonly string[];
    }
  | {
      readonly ok: false;
      readonly failure: ProviderBridgeFailure;
    };

const verificationReferences = (input: VerificationInput): VerificationReferenceValidation => {
  if (input.verificationSecretRefs !== undefined) {
    const references = input.verificationSecretRefs;
    if (
      !Array.isArray(references) ||
      references.length === 0 ||
      references.some(reference => typeof reference !== 'string' || reference.trim().length === 0) ||
      new Set(references).size !== references.length
    ) {
      return {
        ok: false,
        failure: internalFailure(
          'configuration-reference-invalid',
          'Provider verification configuration references are invalid',
        ),
      };
    }
    return { ok: true, references };
  }
  if (input.verificationSecretRef === undefined || input.verificationSecretRef.trim().length === 0) {
    return {
      ok: false,
      failure: internalFailure(
        'configuration-reference-missing',
        'Provider verification configuration reference is missing',
      ),
    };
  }
  return { ok: true, references: [input.verificationSecretRef] };
};

export class MercuryProviderVerifierRegistry implements ProviderVerifierRegistry {
  readonly #configurationReader: ProviderConfigurationReader;
  readonly #now: () => Date;

  constructor(configurationReader: ProviderConfigurationReader, options: ProviderVerifierRegistryOptions = {}) {
    this.#configurationReader = configurationReader;
    this.#now = options.now ?? (() => new Date());
  }

  async verify(input: VerificationInput): Promise<Result<VerificationEvidence, VerificationFailure>> {
    if (!isProviderName(input.provider)) {
      return Err(unsupportedProvider());
    }
    const referenceValidation = verificationReferences(input);
    if (!referenceValidation.ok) {
      return Err(referenceValidation.failure);
    }

    const request: VerificationRequest = {
      rawBody: input.rawBody,
      headers: input.headers,
      registeredUrl: input.registeredUrl,
      receivedAt: this.#now(),
    };

    let verifiedEvidence: VerificationEvidence | undefined;
    let internal: ProviderBridgeFailure | undefined;
    let rejected = false;
    for (const reference of referenceValidation.references) {
      let configuration: unknown;
      try {
        configuration = await this.#configurationReader.read(reference);
      } catch {
        internal ??= internalFailure('configuration-unavailable', 'Provider verification configuration is unavailable');
        continue;
      }
      const validation = validateProviderConfiguration(input.provider, configuration);
      if (!validation.ok) {
        internal ??= validation.failure;
        continue;
      }

      try {
        verifiedEvidence ??= evidenceFrom(await this.#dispatch(validation.provider, request, validation.configuration));
      } catch (error) {
        if (error instanceof VerificationError && error.code === 'invalid_configuration') {
          internal ??= internalFailure('configuration-invalid', 'Provider verification configuration is invalid');
        } else if (error instanceof VerificationDependencyError) {
          internal ??= internalFailure('dependency-unavailable', 'Provider verification dependency is unavailable');
        } else if (error instanceof VerificationError) {
          rejected = true;
        } else {
          internal ??= internalFailure(
            'unexpected-verifier-failure',
            'Provider webhook verification could not be completed',
          );
        }
      }
    }
    if (verifiedEvidence !== undefined) {
      return Ok(verifiedEvidence);
    }
    return Err(
      internal ??
        (rejected
          ? invalidSignature()
          : internalFailure('configuration-missing', 'Provider verification configuration is missing')),
    );
  }

  async #dispatch<Provider extends ProviderName>(
    provider: Provider,
    request: VerificationRequest,
    configuration: ProviderConfigurations[Provider],
  ): Promise<VerifiedWebhook> {
    switch (provider) {
      case 'stripe':
        return stripeVerifier.verify(request, configuration as StripeConfiguration);
      case 'airwallex':
        return airwallexVerifier.verify(request, configuration as AirwallexConfiguration);
      case 'apple-app-store':
        return appleAppStoreVerifier.verify(request, configuration as AppleAppStoreConfiguration);
      case 'google-play':
        return googlePlayVerifier.verify(request, configuration as GooglePlayConfiguration);
      case 'telegram':
        return telegramVerifier.verify(request, configuration as TelegramConfiguration);
      case 'discord':
        return discordVerifier.verify(request, configuration as DiscordConfiguration);
      case 'logto':
        return logtoVerifier.verify(request, configuration as LogtoConfiguration);
    }
  }
}

export const createProviderVerifierRegistry = (
  configurationReader: ProviderConfigurationReader,
  options?: ProviderVerifierRegistryOptions,
): ProviderVerifierRegistry => new MercuryProviderVerifierRegistry(configurationReader, options);
