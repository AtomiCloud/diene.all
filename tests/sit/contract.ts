export const requiredProviderNames = [
  'stripe',
  'airwallex',
  'apple-app-store',
  'google-play',
  'telegram',
  'discord',
  'logto',
] as const;

export type ProviderName = (typeof requiredProviderNames)[number];
export type DeliveryAddressKind = 'canonical' | 'external' | 'local';
export type DeliveryPath = 'cluster-local' | 'public';

export interface RealClaimEvidence {
  readonly claimName: string;
  readonly identity: string;
  readonly implementation: 'real';
  readonly reachable: boolean;
}

export interface UpstashClaimEvidence extends RealClaimEvidence {
  readonly landscape: string;
}

export interface DependencyEvidence {
  readonly neon: RealClaimEvidence;
  readonly upstash: readonly UpstashClaimEvidence[];
  readonly tigris: RealClaimEvidence & { readonly readAfterWriteVerified: boolean };
  readonly secretStore: RealClaimEvidence & { readonly externalSecretsReady: boolean };
  readonly route53: RealClaimEvidence;
  readonly observability: RealClaimEvidence;
}

export interface ProviderVerificationEvidence {
  readonly provider: ProviderName;
  readonly fixtureFormat: string;
  readonly acceptedStatus: number;
  readonly acceptedEventDelta: number;
  readonly forgedStatus: number;
  readonly forgedEventDelta: number;
}

export interface AtomicAcceptanceEvidence {
  readonly provider: ProviderName;
  readonly landingLandscape: string;
  readonly storedEventId: string;
  readonly storedAcknowledgedAtMs: number;
  readonly responseStatus: number;
  readonly responseCompletedAtMs: number;
  readonly firstDeliveryStartedAtMs: number;
  readonly registeredEndpointIds: readonly string[];
  readonly committedEndpointIds: readonly string[];
  readonly dedupExpiresAtMs: number;
  readonly duplicate: {
    readonly responseStatus: number;
    readonly eventDelta: number;
    readonly obligationDelta: number;
    readonly dedupExpiresAtMs: number;
  };
  readonly otherLandscape: {
    readonly landscape: string;
    readonly responseStatus: number;
    readonly eventDelta: number;
    readonly obligationDelta: number;
  };
  readonly failedCommit: {
    readonly responseStatus: number;
    readonly dedupDelta: number;
    readonly eventDelta: number;
    readonly obligationDelta: number;
  };
}

export interface DeliveryEvidence {
  readonly endpointId: string;
  readonly addressKind: DeliveryAddressKind;
  readonly address: string;
  readonly responseStatus: number;
}

export interface FanoutCaseEvidence {
  readonly registeredEndpointIds: readonly string[];
  readonly unregisteredEndpointIds: readonly string[];
  readonly deliveries: readonly DeliveryEvidence[];
}

export interface FanoutEvidence {
  readonly singleRegistration: FanoutCaseEvidence;
  readonly perRowRegistrations: FanoutCaseEvidence;
}

export interface SignedAttemptEvidence {
  readonly kind: 'initial' | 'replay' | 'retry';
  readonly attempt: number;
  readonly replay: boolean;
  readonly timestampSeconds: number;
  readonly signatureHeader: string;
  readonly rawBodyBase64: string;
  readonly consumerStatus: number;
}

export interface RejectedSignatureEvidence {
  readonly path: DeliveryPath;
  readonly mutation: 'forged' | 'stale' | 'stripped';
  readonly consumerStatus: number;
  readonly handlerInvocationDelta: number;
}

export interface SignatureLifecycleEvidence {
  readonly attempts: readonly SignedAttemptEvidence[];
  readonly rejected: readonly RejectedSignatureEvidence[];
}

export interface ConsoleJourneyEvidence {
  readonly loginStatus: number;
  readonly accountName: string;
  readonly queriedLandscapes: readonly string[];
  readonly returnedSourceLandscapes: readonly string[];
  readonly partialFailures: readonly string[];
  readonly replay: {
    readonly requestStatus: number;
    readonly sourceLandscape: string;
    readonly enqueuedLandscape: string;
    readonly endpointId: string;
    readonly replayFlag: boolean;
    readonly freshSignatureAccepted: boolean;
    readonly auditRecorded: boolean;
  };
  readonly preview: {
    readonly gate: 'D11';
    readonly routeStateVisible: boolean;
    readonly callbackDeliveryVisible: boolean;
  };
}

export interface AppleBackfillEvidence {
  readonly competingReplicaCount: number;
  readonly leaseWinnerCount: number;
  readonly fetchedNotificationCount: number;
  readonly acceptedOrDuplicateCount: number;
  readonly ordinaryPipelineCount: number;
  readonly cursorPersistedAfterAcceptance: boolean;
  readonly consecutiveMissedCycles: number;
  readonly missedCycleAlertFired: boolean;
}

export interface GoogleSubscriptionEvidence {
  readonly messageRetentionDays: number;
  readonly deadLetterPolicyExplicit: boolean;
  readonly deadLetterTopic: string;
  readonly oidcServiceAccountEmail: string;
  readonly oidcAudience: string;
  readonly storedRegisteredUrl: string;
  readonly driftDetected: readonly string[];
  readonly driftReconciled: boolean;
}

export interface ArchiveLifecycleEvidence {
  readonly success: {
    readonly uploadedAtMs: number;
    readonly verifiedAtMs: number;
    readonly deletedAtMs: number;
    readonly checksumVerified: boolean;
    readonly liveStreamDeleted: boolean;
  };
  readonly failure: {
    readonly alertFired: boolean;
    readonly deletionBlocked: boolean;
    readonly liveStreamPresent: boolean;
    readonly liveStreamDeleted: boolean;
  };
}

export interface Route53SetEvidence {
  readonly setIdentifier: string;
  readonly policy: 'geoproximity';
  readonly coordinates: {
    readonly latitude: string;
    readonly longitude: string;
  };
  readonly bias: number;
  readonly ttlSeconds: number;
  readonly healthyIngressAddresses: readonly string[];
}

export interface Route53LandingEvidence {
  readonly recordName: string;
  readonly observedSetIdentifier: string;
  readonly providerResponseStatus: number;
  readonly zones: readonly string[];
  readonly sets: readonly Route53SetEvidence[];
  readonly emptyUnhealthySetDeleted: boolean;
  readonly mixedPolicyTypes: boolean;
}

export interface MercuryTestStack {
  close(): Promise<void>;
  inspectDependencies(): Promise<DependencyEvidence>;
  runProviderVerificationMatrix(): Promise<readonly ProviderVerificationEvidence[]>;
  runAtomicAcceptance(): Promise<AtomicAcceptanceEvidence>;
  runFanout(): Promise<FanoutEvidence>;
  runSignatureLifecycle(): Promise<SignatureLifecycleEvidence>;
  runConsoleJourney(): Promise<ConsoleJourneyEvidence>;
  runAppleBackfill(): Promise<AppleBackfillEvidence>;
  inspectGoogleSubscription(): Promise<GoogleSubscriptionEvidence>;
  runArchiveLifecycle(): Promise<ArchiveLifecycleEvidence>;
  inspectRoute53Landing(): Promise<Route53LandingEvidence>;
}

export interface MercuryTestStackFactoryInput {
  readonly environment: Readonly<Record<string, string | undefined>>;
  readonly requiredProviderFixtures: readonly ProviderName[];
}

export type MercuryTestStackFactory = (input: MercuryTestStackFactoryInput) => Promise<MercuryTestStack>;
