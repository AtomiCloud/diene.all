import {
  type AppleBackfillEvidence,
  type ArchiveLifecycleEvidence,
  type AtomicAcceptanceEvidence,
  type ConsoleJourneyEvidence,
  type DependencyEvidence,
  type FanoutEvidence,
  type GoogleSubscriptionEvidence,
  type ProviderVerificationEvidence,
  type Route53LandingEvidence,
  requiredProviderNames,
  type SignatureLifecycleEvidence,
} from './contract.ts';

export interface ScenarioEvidence {
  readonly dependencies: DependencyEvidence;
  readonly 'provider-verification': readonly ProviderVerificationEvidence[];
  readonly 'atomic-acceptance': AtomicAcceptanceEvidence;
  readonly fanout: FanoutEvidence;
  readonly 'signature-lifecycle': SignatureLifecycleEvidence;
  readonly 'console-journey': ConsoleJourneyEvidence;
  readonly 'apple-backfill': AppleBackfillEvidence;
  readonly 'google-subscription': GoogleSubscriptionEvidence;
  readonly 'archive-lifecycle': ArchiveLifecycleEvidence;
  readonly 'route53-landing': Route53LandingEvidence;
}

const acceptedCommitAtMs = 1_800_000_000_000;

export const validScenarioEvidence = {
  dependencies: {
    neon: {
      claimName: 'mercury-neon',
      identity: 'postgresql://mercury-neon',
      implementation: 'real',
      reachable: true,
    },
    upstash: [
      {
        claimName: 'mercury-upstash-serving',
        identity: 'rediss://upstash-serving',
        implementation: 'real',
        reachable: true,
        landscape: 'serving',
      },
      {
        claimName: 'mercury-upstash-primordial',
        identity: 'rediss://upstash-primordial',
        implementation: 'real',
        reachable: true,
        landscape: 'primordial',
      },
    ],
    tigris: {
      claimName: 'mercury-tigris',
      identity: 's3://mercury-archive',
      implementation: 'real',
      reachable: true,
      readAfterWriteVerified: true,
    },
    secretStore: {
      claimName: 'mercury-secrets',
      identity: 'external-secret/mercury',
      implementation: 'real',
      reachable: true,
      externalSecretsReady: true,
    },
    route53: {
      claimName: 'mercury-route53',
      identity: 'hosted-zone/mercury',
      implementation: 'real',
      reachable: true,
    },
    observability: {
      claimName: 'mercury-observability',
      identity: 'grafana/mercury',
      implementation: 'real',
      reachable: true,
    },
  },
  'provider-verification': requiredProviderNames.map(provider => ({
    provider,
    fixtureFormat: `${provider}-signed-v1`,
    acceptedStatus: 200,
    acceptedEventDelta: 1,
    forgedStatus: 401,
    forgedEventDelta: 0,
  })),
  'atomic-acceptance': {
    provider: 'stripe',
    landingLandscape: 'serving',
    storedEventId: 'event-atomic',
    storedAcknowledgedAtMs: acceptedCommitAtMs,
    responseStatus: 200,
    responseCompletedAtMs: acceptedCommitAtMs + 10,
    firstDeliveryStartedAtMs: acceptedCommitAtMs + 20,
    registeredEndpointIds: ['endpoint-alpha', 'endpoint-beta'],
    committedEndpointIds: ['endpoint-alpha', 'endpoint-beta'],
    dedupExpiresAtMs: acceptedCommitAtMs + 72 * 60 * 60 * 1_000,
    duplicate: {
      responseStatus: 200,
      eventDelta: 0,
      obligationDelta: 0,
      dedupExpiresAtMs: acceptedCommitAtMs + 72 * 60 * 60 * 1_000,
    },
    otherLandscape: {
      landscape: 'primordial',
      responseStatus: 200,
      eventDelta: 1,
      obligationDelta: 2,
    },
    failedCommit: {
      responseStatus: 503,
      dedupDelta: 0,
      eventDelta: 0,
      obligationDelta: 0,
    },
  },
  fanout: {
    singleRegistration: {
      registeredEndpointIds: ['endpoint-single'],
      unregisteredEndpointIds: ['endpoint-not-registered'],
      deliveries: [
        {
          endpointId: 'endpoint-single',
          addressKind: 'local',
          address: 'http://endpoint-single.svc.cluster.local/webhook',
          responseStatus: 200,
        },
      ],
    },
    perRowRegistrations: {
      registeredEndpointIds: ['endpoint-one', 'endpoint-two', 'endpoint-three'],
      unregisteredEndpointIds: ['endpoint-four'],
      deliveries: [
        {
          endpointId: 'endpoint-one',
          addressKind: 'canonical',
          address: 'https://hooks.webhook.mercury.serving.cluster.atomi.cloud/one',
          responseStatus: 200,
        },
        {
          endpointId: 'endpoint-two',
          addressKind: 'local',
          address: 'http://endpoint-two.svc.cluster.local/webhook',
          responseStatus: 200,
        },
        {
          endpointId: 'endpoint-three',
          addressKind: 'external',
          address: 'https://consumer.example.test/webhook',
          responseStatus: 200,
        },
      ],
    },
  },
  'signature-lifecycle': {
    attempts: [
      {
        kind: 'initial',
        attempt: 1,
        replay: false,
        timestampSeconds: 1_800_000_000,
        signatureHeader: `t=1800000000,v1=${'a'.repeat(64)}`,
        rawBodyBase64: 'eyJpZCI6ImV2dCJ9',
        consumerStatus: 200,
      },
      {
        kind: 'retry',
        attempt: 2,
        replay: false,
        timestampSeconds: 1_800_000_001,
        signatureHeader: `t=1800000001,v1=${'b'.repeat(64)}`,
        rawBodyBase64: 'eyJpZCI6ImV2dCJ9',
        consumerStatus: 200,
      },
      {
        kind: 'replay',
        attempt: 3,
        replay: true,
        timestampSeconds: 1_800_000_002,
        signatureHeader: `t=1800000002,v1=${'c'.repeat(64)}`,
        rawBodyBase64: 'eyJpZCI6ImV2dCJ9',
        consumerStatus: 200,
      },
    ],
    rejected: [
      { path: 'cluster-local', mutation: 'forged', consumerStatus: 401, handlerInvocationDelta: 0 },
      { path: 'cluster-local', mutation: 'stale', consumerStatus: 401, handlerInvocationDelta: 0 },
      { path: 'cluster-local', mutation: 'stripped', consumerStatus: 401, handlerInvocationDelta: 0 },
      { path: 'public', mutation: 'forged', consumerStatus: 401, handlerInvocationDelta: 0 },
      { path: 'public', mutation: 'stale', consumerStatus: 401, handlerInvocationDelta: 0 },
      { path: 'public', mutation: 'stripped', consumerStatus: 401, handlerInvocationDelta: 0 },
    ],
  },
  'console-journey': {
    loginStatus: 200,
    accountName: 'internal/default',
    queriedLandscapes: ['serving', 'primordial'],
    returnedSourceLandscapes: ['serving', 'primordial'],
    partialFailures: [],
    replay: {
      requestStatus: 202,
      sourceLandscape: 'serving',
      enqueuedLandscape: 'serving',
      endpointId: 'endpoint-alpha',
      replayFlag: true,
      freshSignatureAccepted: true,
      auditRecorded: true,
    },
    preview: {
      gate: 'D11',
      routeStateVisible: true,
      callbackDeliveryVisible: false,
    },
  },
  'apple-backfill': {
    competingReplicaCount: 2,
    leaseWinnerCount: 1,
    fetchedNotificationCount: 3,
    acceptedOrDuplicateCount: 3,
    ordinaryPipelineCount: 3,
    cursorPersistedAfterAcceptance: true,
    consecutiveMissedCycles: 3,
    missedCycleAlertFired: true,
  },
  'google-subscription': {
    messageRetentionDays: 31,
    deadLetterPolicyExplicit: true,
    deadLetterTopic: 'projects/mercury/topics/dead-letter',
    oidcServiceAccountEmail: 'mercury-push@example.test',
    oidcAudience: 'https://hooks.webhook.mercury.serving.cluster.atomi.cloud/google-play',
    storedRegisteredUrl: 'https://hooks.webhook.mercury.serving.cluster.atomi.cloud/google-play',
    driftDetected: ['deadLetterPolicy', 'messageRetention', 'oidcAudience', 'oidcServiceAccount', 'pushEndpoint'],
    driftReconciled: true,
  },
  'archive-lifecycle': {
    success: {
      uploadedAtMs: acceptedCommitAtMs,
      verifiedAtMs: acceptedCommitAtMs + 10,
      deletedAtMs: acceptedCommitAtMs + 20,
      checksumVerified: true,
      liveStreamDeleted: true,
    },
    failure: {
      alertFired: true,
      deletionBlocked: true,
      liveStreamPresent: true,
      liveStreamDeleted: false,
    },
  },
  'route53-landing': {
    recordName: 'hooks.webhook.mercury.serving.cluster.atomi.cloud',
    observedSetIdentifier: 'serving-eu',
    providerResponseStatus: 200,
    zones: ['eu-central-1a', 'eu-central-1b'],
    sets: [
      {
        setIdentifier: 'serving-eu',
        policy: 'geoproximity',
        coordinates: { latitude: '52.52', longitude: '13.40' },
        bias: 0,
        ttlSeconds: 60,
        healthyIngressAddresses: ['203.0.113.10'],
      },
      {
        setIdentifier: 'primordial-us',
        policy: 'geoproximity',
        coordinates: { latitude: '40.71', longitude: '-74.01' },
        bias: 10,
        ttlSeconds: 60,
        healthyIngressAddresses: ['198.51.100.20'],
      },
    ],
    emptyUnhealthySetDeleted: true,
    mixedPolicyTypes: false,
  },
} as const satisfies ScenarioEvidence;
