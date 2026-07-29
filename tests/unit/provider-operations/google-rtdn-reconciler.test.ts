import { describe, expect, test } from 'bun:test';
import { Err, Ok, type Result } from '@atomicloud/diene.result';
import {
  GOOGLE_PLAY_RTDN_MESSAGE_RETENTION_SECONDS,
  GooglePlayRtdnSubscriptionReconciler,
  type GooglePubSubAdminFailure,
  type GooglePubSubAdministrationClient,
  type GooglePubSubDesiredState,
  type GooglePubSubSubscriptionState,
  type GooglePubSubUpdateField,
  inspectGooglePubSubDrift,
} from '../../../src/provider-operations/google-rtdn-reconciler.ts';

const subscriptionName = 'projects/atomi/subscriptions/mercury-google-play';
const deadLetterTopic = 'projects/atomi/topics/google-play-rtdn-dead-letter';
const pushUrl = 'https://hooks.example.test/t/acme/google-play';
const serviceAccountEmail = 'pubsub-push@atomi.iam.gserviceaccount.com';

const desiredState: GooglePubSubDesiredState = {
  messageRetentionSeconds: GOOGLE_PLAY_RTDN_MESSAGE_RETENTION_SECONDS,
  deadLetterPolicy: {
    deadLetterTopic,
    maxDeliveryAttempts: 12,
  },
  pushConfig: {
    pushUrl,
    oidcServiceAccountEmail: serviceAccountEmail,
    oidcAudience: pushUrl,
  },
};

class FakeGoogleAdmin implements GooglePubSubAdministrationClient {
  updates: Array<{
    readonly name: string;
    readonly desired: GooglePubSubDesiredState;
    readonly updateMask: readonly GooglePubSubUpdateField[];
  }> = [];

  constructor(
    readonly current: Result<GooglePubSubSubscriptionState, GooglePubSubAdminFailure>,
    readonly repaired: Result<GooglePubSubSubscriptionState, GooglePubSubAdminFailure> = Ok({
      name: subscriptionName,
      ...desiredState,
    }),
  ) {}

  async getSubscription(): Promise<Result<GooglePubSubSubscriptionState, GooglePubSubAdminFailure>> {
    return this.current;
  }

  async updateSubscription(input: {
    readonly name: string;
    readonly desired: GooglePubSubDesiredState;
    readonly updateMask: readonly GooglePubSubUpdateField[];
  }): Promise<Result<GooglePubSubSubscriptionState, GooglePubSubAdminFailure>> {
    this.updates.push(input);
    return this.repaired;
  }
}

const reconciler = (
  client: GooglePubSubAdministrationClient,
  oidcAudience?: string,
): GooglePlayRtdnSubscriptionReconciler =>
  new GooglePlayRtdnSubscriptionReconciler(client, {
    subscriptionName,
    deadLetterTopic,
    deadLetterMaxDeliveryAttempts: 12,
    registeredPushUrl: pushUrl,
    oidcServiceAccountEmail: serviceAccountEmail,
    ...(oidcAudience === undefined ? {} : { oidcAudience }),
  });

describe('Google Play RTDN subscription reconciliation', () => {
  test('builds the exact desired state and defaults an omitted audience to the push URL', () => {
    const client = new FakeGoogleAdmin(Ok({ name: subscriptionName, ...desiredState }));
    expect(reconciler(client).desired).toEqual(desiredState);
    expect(reconciler(client, 'https://audience.example.test').desired).toEqual({
      ...desiredState,
      pushConfig: {
        ...desiredState.pushConfig,
        oidcAudience: 'https://audience.example.test',
      },
    });
    expect(GOOGLE_PLAY_RTDN_MESSAGE_RETENTION_SECONDS).toBe(2_678_400);
  });

  test('reports every drift dimension and repairs the grouped fields once', async () => {
    const drifted: GooglePubSubSubscriptionState = {
      name: subscriptionName,
      messageRetentionSeconds: 600,
      deadLetterPolicy: {
        deadLetterTopic: 'projects/atomi/topics/wrong',
        maxDeliveryAttempts: 5,
      },
      pushConfig: {
        pushUrl: 'https://wrong.example.test',
        oidcServiceAccountEmail: 'wrong@atomi.iam.gserviceaccount.com',
        oidcAudience: 'https://wrong-audience.example.test',
      },
    };
    expect(inspectGooglePubSubDrift(drifted, desiredState).map(item => item.dimension)).toEqual([
      'message-retention',
      'dead-letter-topic',
      'dead-letter-max-delivery-attempts',
      'push-url',
      'oidc-service-account-email',
      'oidc-audience',
    ]);

    const client = new FakeGoogleAdmin(Ok(drifted));
    const report = await (await reconciler(client).reconcile()).unwrap();
    expect(report.status).toBe('repaired');
    expect(report.drift).toHaveLength(6);
    expect(report.repair).toEqual({
      updateMask: ['messageRetentionDuration', 'deadLetterPolicy', 'pushConfig'],
      observed: { name: subscriptionName, ...desiredState },
    });
    expect(client.updates).toEqual([
      {
        name: subscriptionName,
        desired: desiredState,
        updateMask: ['messageRetentionDuration', 'deadLetterPolicy', 'pushConfig'],
      },
    ]);
  });

  test('is an idempotent no-op when the subscription is already exact', async () => {
    const client = new FakeGoogleAdmin(Ok({ name: subscriptionName, ...desiredState }));
    const result = await reconciler(client).reconcile();
    expect(await result.unwrap()).toEqual({
      status: 'in-sync',
      desired: desiredState,
      drift: [],
    });
    expect(client.updates).toHaveLength(0);
  });

  test('contains repair failures and never propagates credential-bearing details', async () => {
    const secret = 'ya29.super-secret-access-token';
    const drifted = {
      name: subscriptionName,
      ...desiredState,
      messageRetentionSeconds: 60,
    };
    const client = new FakeGoogleAdmin(
      Ok(drifted),
      Err({
        code: 'authentication',
        message: `upstream rejected ${secret}`,
        retryable: false,
      }),
    );
    const failure = await (await reconciler(client).reconcile()).unwrapErr();
    expect(failure).toMatchObject({
      code: 'repair-failed',
      message: 'Google Pub/Sub subscription repair failed (authentication)',
      retryable: false,
    });
    expect(JSON.stringify(failure)).not.toContain(secret);
  });

  test('reports non-converging repair evidence as a contained failure', async () => {
    const drifted = {
      name: subscriptionName,
      ...desiredState,
      messageRetentionSeconds: 60,
    };
    const client = new FakeGoogleAdmin(Ok(drifted), Ok(drifted));
    const failure = await (await reconciler(client).reconcile()).unwrapErr();
    expect(failure).toMatchObject({
      code: 'repair-incomplete',
      remainingDrift: [{ dimension: 'message-retention' }],
    });
  });
});
