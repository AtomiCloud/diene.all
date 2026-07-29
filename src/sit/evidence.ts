import { z } from 'zod';

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

const nonEmptyString = z.string().min(1);
const nonNegativeInteger = z.number().int().nonnegative();
const statusCode = z.number().int().min(100).max(599);
const timestampMs = nonNegativeInteger;

const realClaimSchema = z
  .object({
    claimName: nonEmptyString,
    identity: nonEmptyString,
    implementation: z.literal('real'),
    reachable: z.boolean(),
  })
  .strict();

export const dependencyEvidenceSchema = z
  .object({
    neon: realClaimSchema,
    upstash: z.array(
      realClaimSchema
        .extend({
          landscape: nonEmptyString,
        })
        .strict(),
    ),
    tigris: realClaimSchema
      .extend({
        readAfterWriteVerified: z.boolean(),
      })
      .strict(),
    secretStore: realClaimSchema
      .extend({
        externalSecretsReady: z.boolean(),
      })
      .strict(),
    route53: realClaimSchema,
    observability: realClaimSchema,
  })
  .strict();

const providerVerificationEvidenceSchema = z
  .object({
    provider: z.enum(providerNames),
    fixtureFormat: nonEmptyString,
    acceptedStatus: statusCode,
    acceptedEventDelta: nonNegativeInteger,
    forgedStatus: statusCode,
    forgedEventDelta: nonNegativeInteger,
  })
  .strict();

export const providerVerificationMatrixSchema = z
  .array(providerVerificationEvidenceSchema)
  .length(providerNames.length)
  .refine(
    evidence =>
      new Set(evidence.map(item => item.provider)).size === providerNames.length &&
      providerNames.every(provider => evidence.some(item => item.provider === provider)),
    'provider verification evidence must contain each exact v1 provider once',
  );

export const atomicAcceptanceEvidenceSchema = z
  .object({
    provider: z.enum(providerNames),
    landingLandscape: nonEmptyString,
    storedEventId: nonEmptyString,
    storedAcknowledgedAtMs: timestampMs,
    responseStatus: statusCode,
    responseCompletedAtMs: timestampMs,
    firstDeliveryStartedAtMs: timestampMs,
    registeredEndpointIds: z.array(nonEmptyString),
    committedEndpointIds: z.array(nonEmptyString),
    dedupExpiresAtMs: timestampMs,
    duplicate: z
      .object({
        responseStatus: statusCode,
        eventDelta: nonNegativeInteger,
        obligationDelta: nonNegativeInteger,
        dedupExpiresAtMs: timestampMs,
      })
      .strict(),
    otherLandscape: z
      .object({
        landscape: nonEmptyString,
        responseStatus: statusCode,
        eventDelta: nonNegativeInteger,
        obligationDelta: nonNegativeInteger,
      })
      .strict(),
    failedCommit: z
      .object({
        responseStatus: statusCode,
        dedupDelta: nonNegativeInteger,
        eventDelta: nonNegativeInteger,
        obligationDelta: nonNegativeInteger,
      })
      .strict(),
  })
  .strict();

const deliveryEvidenceSchema = z
  .object({
    endpointId: nonEmptyString,
    addressKind: z.enum(['canonical', 'external', 'local']),
    address: nonEmptyString,
    responseStatus: statusCode,
  })
  .strict();

const fanoutCaseEvidenceSchema = z
  .object({
    registeredEndpointIds: z.array(nonEmptyString),
    unregisteredEndpointIds: z.array(nonEmptyString),
    deliveries: z.array(deliveryEvidenceSchema),
  })
  .strict();

export const fanoutEvidenceSchema = z
  .object({
    singleRegistration: fanoutCaseEvidenceSchema,
    perRowRegistrations: fanoutCaseEvidenceSchema,
  })
  .strict();

const signedAttemptEvidenceSchema = z
  .object({
    kind: z.enum(['initial', 'replay', 'retry']),
    attempt: nonNegativeInteger,
    replay: z.boolean(),
    timestampSeconds: nonNegativeInteger,
    signatureHeader: nonEmptyString,
    rawBodyBase64: nonEmptyString,
    consumerStatus: statusCode,
  })
  .strict();

const rejectedSignatureEvidenceSchema = z
  .object({
    path: z.enum(['cluster-local', 'public']),
    mutation: z.enum(['forged', 'stale', 'stripped']),
    consumerStatus: statusCode,
    handlerInvocationDelta: nonNegativeInteger,
  })
  .strict();

export const signatureLifecycleEvidenceSchema = z
  .object({
    attempts: z.array(signedAttemptEvidenceSchema),
    rejected: z.array(rejectedSignatureEvidenceSchema),
  })
  .strict();

export const consoleJourneyEvidenceSchema = z
  .object({
    loginStatus: statusCode,
    accountName: nonEmptyString,
    queriedLandscapes: z.array(nonEmptyString),
    returnedSourceLandscapes: z.array(nonEmptyString),
    partialFailures: z.array(nonEmptyString),
    replay: z
      .object({
        requestStatus: statusCode,
        sourceLandscape: nonEmptyString,
        enqueuedLandscape: nonEmptyString,
        endpointId: nonEmptyString,
        replayFlag: z.boolean(),
        freshSignatureAccepted: z.boolean(),
        auditRecorded: z.boolean(),
      })
      .strict(),
    preview: z
      .object({
        gate: z.literal('D11'),
        routeStateVisible: z.boolean(),
        callbackDeliveryVisible: z.boolean(),
      })
      .strict(),
  })
  .strict();

export const appleBackfillEvidenceSchema = z
  .object({
    competingReplicaCount: nonNegativeInteger,
    leaseWinnerCount: nonNegativeInteger,
    fetchedNotificationCount: nonNegativeInteger,
    acceptedOrDuplicateCount: nonNegativeInteger,
    ordinaryPipelineCount: nonNegativeInteger,
    cursorPersistedAfterAcceptance: z.boolean(),
    consecutiveMissedCycles: nonNegativeInteger,
    missedCycleAlertFired: z.boolean(),
  })
  .strict();

export const googleSubscriptionEvidenceSchema = z
  .object({
    messageRetentionDays: nonNegativeInteger,
    deadLetterPolicyExplicit: z.boolean(),
    deadLetterTopic: nonEmptyString,
    oidcServiceAccountEmail: nonEmptyString,
    oidcAudience: nonEmptyString,
    storedRegisteredUrl: nonEmptyString,
    driftDetected: z.array(nonEmptyString),
    driftReconciled: z.boolean(),
  })
  .strict();

export const archiveLifecycleEvidenceSchema = z
  .object({
    success: z
      .object({
        uploadedAtMs: timestampMs,
        verifiedAtMs: timestampMs,
        deletedAtMs: timestampMs,
        checksumVerified: z.boolean(),
        liveStreamDeleted: z.boolean(),
      })
      .strict(),
    failure: z
      .object({
        alertFired: z.boolean(),
        deletionBlocked: z.boolean(),
        liveStreamPresent: z.boolean(),
        liveStreamDeleted: z.boolean(),
      })
      .strict(),
  })
  .strict();

const route53SetEvidenceSchema = z
  .object({
    setIdentifier: nonEmptyString,
    policy: z.literal('geoproximity'),
    coordinates: z
      .object({
        latitude: z.string().regex(/^-?\d+(?:\.\d{1,2})?$/),
        longitude: z.string().regex(/^-?\d+(?:\.\d{1,2})?$/),
      })
      .strict(),
    bias: z.number().int().min(-99).max(99),
    ttlSeconds: z.number().int().positive(),
    healthyIngressAddresses: z.array(nonEmptyString),
  })
  .strict();

export const route53LandingEvidenceSchema = z
  .object({
    recordName: nonEmptyString,
    observedSetIdentifier: nonEmptyString,
    providerResponseStatus: statusCode,
    zones: z.array(nonEmptyString),
    sets: z.array(route53SetEvidenceSchema),
    emptyUnhealthySetDeleted: z.boolean(),
    mixedPolicyTypes: z.boolean(),
  })
  .strict();

export const sessionEvidenceSchema = z
  .object({
    sessionId: z
      .string()
      .max(128)
      .regex(/^[A-Za-z0-9._~-]+$/)
      .refine(value => value !== '.' && value !== '..', 'session ID must be a safe path segment'),
  })
  .strict();

export type DependencyEvidence = z.infer<typeof dependencyEvidenceSchema>;
export type ProviderVerificationEvidence = z.infer<typeof providerVerificationMatrixSchema>[number];
export type AtomicAcceptanceEvidence = z.infer<typeof atomicAcceptanceEvidenceSchema>;
export type FanoutEvidence = z.infer<typeof fanoutEvidenceSchema>;
export type SignatureLifecycleEvidence = z.infer<typeof signatureLifecycleEvidenceSchema>;
export type ConsoleJourneyEvidence = z.infer<typeof consoleJourneyEvidenceSchema>;
export type AppleBackfillEvidence = z.infer<typeof appleBackfillEvidenceSchema>;
export type GoogleSubscriptionEvidence = z.infer<typeof googleSubscriptionEvidenceSchema>;
export type ArchiveLifecycleEvidence = z.infer<typeof archiveLifecycleEvidenceSchema>;
export type Route53LandingEvidence = z.infer<typeof route53LandingEvidenceSchema>;
