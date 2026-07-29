import { Err, Ok, type Result } from '@atomicloud/diene.result';

export const GOOGLE_PLAY_RTDN_MESSAGE_RETENTION_SECONDS = 31 * 24 * 60 * 60;

interface GooglePubSubDeadLetterPolicy {
  readonly deadLetterTopic: string;
  readonly maxDeliveryAttempts: number;
}

interface GooglePubSubPushConfig {
  readonly pushUrl: string;
  readonly oidcServiceAccountEmail: string;
  readonly oidcAudience: string;
}

export interface GooglePubSubSubscriptionState {
  readonly name: string;
  readonly messageRetentionSeconds: number;
  readonly deadLetterPolicy?: GooglePubSubDeadLetterPolicy;
  readonly pushConfig?: GooglePubSubPushConfig;
}

export interface GooglePubSubDesiredState {
  readonly messageRetentionSeconds: number;
  /**
   * This is Google Pub/Sub's dead-letter policy. It is independent from, and
   * must not be configured as, a Mercury endpoint-delivery dead-letter queue.
   */
  readonly deadLetterPolicy: GooglePubSubDeadLetterPolicy;
  readonly pushConfig: GooglePubSubPushConfig;
}

export interface GooglePubSubAdminFailure {
  readonly code: 'authentication' | 'cancelled' | 'http' | 'network' | 'protocol' | 'timeout';
  readonly message: string;
  readonly retryable: boolean;
  readonly status?: number;
}

export interface GooglePubSubAdministrationClient {
  getSubscription(
    name: string,
    signal?: AbortSignal,
  ): Promise<Result<GooglePubSubSubscriptionState, GooglePubSubAdminFailure>>;

  updateSubscription(
    input: {
      readonly name: string;
      readonly desired: GooglePubSubDesiredState;
      readonly updateMask: readonly GooglePubSubUpdateField[];
    },
    signal?: AbortSignal,
  ): Promise<Result<GooglePubSubSubscriptionState, GooglePubSubAdminFailure>>;
}

type GooglePubSubDriftDimension =
  | 'dead-letter-max-delivery-attempts'
  | 'dead-letter-topic'
  | 'message-retention'
  | 'oidc-audience'
  | 'oidc-service-account-email'
  | 'push-url';

export type GooglePubSubUpdateField = 'deadLetterPolicy' | 'messageRetentionDuration' | 'pushConfig';

export interface GooglePubSubDrift {
  readonly dimension: GooglePubSubDriftDimension;
  readonly actual: string | number | null;
  readonly desired: string | number;
}

export interface GooglePlayRtdnReconcilerOptions {
  readonly subscriptionName: string;
  readonly deadLetterTopic: string;
  readonly deadLetterMaxDeliveryAttempts: number;
  readonly registeredPushUrl: string;
  readonly oidcServiceAccountEmail: string;
  /**
   * When intentionally omitted, Google must receive the registered push URL
   * as the audience rather than an absent/default audience.
   */
  readonly oidcAudience?: string;
}

export interface GooglePlayRtdnReconciliationReport {
  readonly status: 'in-sync' | 'repaired';
  readonly desired: GooglePubSubDesiredState;
  readonly drift: readonly GooglePubSubDrift[];
  readonly repair?: {
    readonly updateMask: readonly GooglePubSubUpdateField[];
    readonly observed: GooglePubSubSubscriptionState;
  };
}

export interface GooglePlayRtdnReconciliationFailure {
  readonly code: 'inspect-failed' | 'repair-failed' | 'repair-incomplete';
  readonly message: string;
  readonly retryable: boolean;
  readonly drift: readonly GooglePubSubDrift[];
  readonly remainingDrift?: readonly GooglePubSubDrift[];
}

const validateOptions = (options: GooglePlayRtdnReconcilerOptions): void => {
  if (
    options.subscriptionName.length === 0 ||
    options.deadLetterTopic.length === 0 ||
    options.registeredPushUrl.length === 0 ||
    options.oidcServiceAccountEmail.length === 0 ||
    options.oidcAudience === ''
  ) {
    throw new TypeError('Google Play RTDN subscription settings are required');
  }
  if (
    !Number.isSafeInteger(options.deadLetterMaxDeliveryAttempts) ||
    options.deadLetterMaxDeliveryAttempts < 5 ||
    options.deadLetterMaxDeliveryAttempts > 100
  ) {
    throw new RangeError('Google Pub/Sub dead-letter max delivery attempts must be between 5 and 100');
  }
};

const desiredState = (options: GooglePlayRtdnReconcilerOptions): GooglePubSubDesiredState => ({
  messageRetentionSeconds: GOOGLE_PLAY_RTDN_MESSAGE_RETENTION_SECONDS,
  deadLetterPolicy: {
    deadLetterTopic: options.deadLetterTopic,
    maxDeliveryAttempts: options.deadLetterMaxDeliveryAttempts,
  },
  pushConfig: {
    pushUrl: options.registeredPushUrl,
    oidcServiceAccountEmail: options.oidcServiceAccountEmail,
    oidcAudience: options.oidcAudience ?? options.registeredPushUrl,
  },
});

export const inspectGooglePubSubDrift = (
  actual: GooglePubSubSubscriptionState,
  desired: GooglePubSubDesiredState,
): readonly GooglePubSubDrift[] => {
  const drift: GooglePubSubDrift[] = [];
  if (actual.messageRetentionSeconds !== desired.messageRetentionSeconds) {
    drift.push({
      dimension: 'message-retention',
      actual: actual.messageRetentionSeconds,
      desired: desired.messageRetentionSeconds,
    });
  }
  if (actual.deadLetterPolicy?.deadLetterTopic !== desired.deadLetterPolicy.deadLetterTopic) {
    drift.push({
      dimension: 'dead-letter-topic',
      actual: actual.deadLetterPolicy?.deadLetterTopic ?? null,
      desired: desired.deadLetterPolicy.deadLetterTopic,
    });
  }
  if (actual.deadLetterPolicy?.maxDeliveryAttempts !== desired.deadLetterPolicy.maxDeliveryAttempts) {
    drift.push({
      dimension: 'dead-letter-max-delivery-attempts',
      actual: actual.deadLetterPolicy?.maxDeliveryAttempts ?? null,
      desired: desired.deadLetterPolicy.maxDeliveryAttempts,
    });
  }
  if (actual.pushConfig?.pushUrl !== desired.pushConfig.pushUrl) {
    drift.push({
      dimension: 'push-url',
      actual: actual.pushConfig?.pushUrl ?? null,
      desired: desired.pushConfig.pushUrl,
    });
  }
  if (actual.pushConfig?.oidcServiceAccountEmail !== desired.pushConfig.oidcServiceAccountEmail) {
    drift.push({
      dimension: 'oidc-service-account-email',
      actual: actual.pushConfig?.oidcServiceAccountEmail ?? null,
      desired: desired.pushConfig.oidcServiceAccountEmail,
    });
  }
  if (actual.pushConfig?.oidcAudience !== desired.pushConfig.oidcAudience) {
    drift.push({
      dimension: 'oidc-audience',
      actual: actual.pushConfig?.oidcAudience ?? null,
      desired: desired.pushConfig.oidcAudience,
    });
  }
  return drift;
};

const updateMaskFor = (drift: readonly GooglePubSubDrift[]): readonly GooglePubSubUpdateField[] => {
  const dimensions = new Set(drift.map(item => item.dimension));
  const updateMask: GooglePubSubUpdateField[] = [];
  if (dimensions.has('message-retention')) {
    updateMask.push('messageRetentionDuration');
  }
  if (dimensions.has('dead-letter-topic') || dimensions.has('dead-letter-max-delivery-attempts')) {
    updateMask.push('deadLetterPolicy');
  }
  if (dimensions.has('push-url') || dimensions.has('oidc-service-account-email') || dimensions.has('oidc-audience')) {
    updateMask.push('pushConfig');
  }
  return updateMask;
};

export class GooglePlayRtdnSubscriptionReconciler {
  readonly desired: GooglePubSubDesiredState;

  constructor(
    readonly client: GooglePubSubAdministrationClient,
    readonly options: GooglePlayRtdnReconcilerOptions,
  ) {
    validateOptions(options);
    this.desired = desiredState(options);
  }

  async reconcile(
    signal?: AbortSignal,
  ): Promise<Result<GooglePlayRtdnReconciliationReport, GooglePlayRtdnReconciliationFailure>> {
    const currentResult = await this.client.getSubscription(this.options.subscriptionName, signal);
    if (await currentResult.isErr()) {
      const failure = await currentResult.unwrapErr();
      return Err({
        code: 'inspect-failed',
        message: `Google Pub/Sub subscription inspection failed (${failure.code})`,
        retryable: failure.retryable,
        drift: [],
      });
    }

    const current = await currentResult.unwrap();
    const drift = inspectGooglePubSubDrift(current, this.desired);
    if (drift.length === 0) {
      return Ok({
        status: 'in-sync',
        desired: this.desired,
        drift,
      });
    }

    const updateMask = updateMaskFor(drift);
    const repairedResult = await this.client.updateSubscription(
      {
        name: this.options.subscriptionName,
        desired: this.desired,
        updateMask,
      },
      signal,
    );
    if (await repairedResult.isErr()) {
      const failure = await repairedResult.unwrapErr();
      return Err({
        code: 'repair-failed',
        message: `Google Pub/Sub subscription repair failed (${failure.code})`,
        retryable: failure.retryable,
        drift,
      });
    }

    const repaired = await repairedResult.unwrap();
    const remainingDrift = inspectGooglePubSubDrift(repaired, this.desired);
    if (remainingDrift.length > 0) {
      return Err({
        code: 'repair-incomplete',
        message: 'Google Pub/Sub subscription repair did not converge',
        retryable: true,
        drift,
        remainingDrift,
      });
    }
    return Ok({
      status: 'repaired',
      desired: this.desired,
      drift,
      repair: {
        updateMask,
        observed: repaired,
      },
    });
  }
}
