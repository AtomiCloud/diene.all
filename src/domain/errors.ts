type StorageFailureCode = 'conflict' | 'invalid-data' | 'unavailable';

export interface StorageFailure {
  readonly code: StorageFailureCode;
  readonly operation: string;
  readonly message: string;
}

export interface VerificationFailure {
  readonly code: 'invalid-signature' | 'missing-credential' | 'unsupported-provider';
  readonly message: string;
}

type IntakeFailureCode =
  | 'config-unavailable'
  | 'persistence-unavailable'
  | 'quota-exhausted'
  | 'unknown-route'
  | 'verification-failed';

export interface IntakeFailure {
  readonly code: IntakeFailureCode;
  readonly message: string;
  readonly retryAfterSeconds?: number;
  readonly landscape?: string;
  readonly provider?: string;
  readonly tenantId?: string;
}

export interface DeliveryFailure {
  readonly code: 'config-unavailable' | 'secret-unavailable' | 'storage-unavailable';
  readonly message: string;
}

type SecretReadFailureCode = 'invalid-reference' | 'not-file' | 'not-found' | 'too-large' | 'unavailable';

export interface SecretReadFailure {
  readonly code: SecretReadFailureCode;
  readonly message: string;
}

type RuntimeJobFailureCode = 'cancelled' | 'delivery-failed' | 'retention-failed' | 'storage-unavailable';

export interface RuntimeJobFailure {
  readonly code: RuntimeJobFailureCode;
  readonly message: string;
  readonly retryable: boolean;
}

export interface TransportFailure {
  readonly code: 'cancelled' | 'network' | 'timeout' | 'unavailable';
  readonly message: string;
}

export interface ArchiveFailure {
  readonly code: 'unavailable';
  readonly message: string;
}
