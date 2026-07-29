export const providerNames = [
  'stripe',
  'airwallex',
  'apple-app-store',
  'google-play',
  'telegram',
  'discord',
  'logto',
] as const;

export type ProviderName = (typeof providerNames)[number];

export type VerificationHeaders = Readonly<Record<string, string | undefined>>;

export interface VerificationRequest {
  readonly rawBody: Uint8Array;
  readonly headers: VerificationHeaders;
  /**
   * The exact URL stored with the route. Verifiers must never reconstruct it
   * from request headers.
   */
  readonly registeredUrl: string;
  readonly receivedAt?: Date;
}

export interface ProviderMetadata {
  readonly eventId?: string;
  readonly eventType?: string;
  readonly providerTimestamp?: number;
  readonly sequence?: string;
}

export interface VerifiedWebhook {
  readonly provider: ProviderName;
  readonly dedupId: string;
  /** Verified provider material used only for fallback dedup derivation. */
  readonly signatureMaterial: string;
  readonly metadata: ProviderMetadata;
}

export interface ProviderVerifier<Configuration> {
  readonly provider: ProviderName;
  verify(request: VerificationRequest, configuration: Configuration): Promise<VerifiedWebhook>;
}

export type VerificationErrorCode =
  | 'invalid_certificate'
  | 'invalid_claims'
  | 'invalid_configuration'
  | 'invalid_signature'
  | 'malformed_header'
  | 'malformed_payload'
  | 'missing_header'
  | 'timestamp_skew'
  | 'unsupported_algorithm'
  | 'wrong_target';

export class VerificationError extends Error {
  readonly code: VerificationErrorCode;

  constructor(code: VerificationErrorCode, message: string, options?: ErrorOptions) {
    super(message, options);
    this.name = 'VerificationError';
    this.code = code;
  }
}

export type VerificationDependencyErrorCode = 'key_resolution_failed' | 'remote_verifier_unavailable';

/**
 * A verifier dependency failed before request authenticity could be decided.
 * These failures are retryable infrastructure faults, never forged requests.
 */
export class VerificationDependencyError extends Error {
  readonly code: VerificationDependencyErrorCode;
  readonly retryable = true;

  constructor(code: VerificationDependencyErrorCode, message: string, options?: ErrorOptions) {
    super(message, options);
    this.name = 'VerificationDependencyError';
    this.code = code;
  }
}
