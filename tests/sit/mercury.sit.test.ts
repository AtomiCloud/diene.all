import { afterAll, beforeAll, describe, it } from 'bun:test';
import should from 'should';
import { type FanoutCaseEvidence, type MercuryTestStack, requiredProviderNames } from './contract.ts';
import { loadMercuryTestStack } from './stack-adapter.ts';

const HOUR_MS = 60 * 60 * 1_000;

const sorted = (values: readonly string[]): string[] => [...values].sort();

const assertSuccessfulStatus = (status: number): void => {
  should(status >= 200 && status < 300).be.true();
};

const assertFanoutCase = (actual: FanoutCaseEvidence, expectedCardinality: number): void => {
  const registered = sorted(actual.registeredEndpointIds);
  const delivered = sorted(actual.deliveries.map(delivery => delivery.endpointId));

  should(registered).have.length(expectedCardinality);
  should(new Set(registered).size).equal(expectedCardinality);
  should(delivered).deepEqual(registered);
  should(actual.deliveries).have.length(expectedCardinality);
  should(actual.unregisteredEndpointIds.length > 0).be.true();

  for (const endpointId of actual.unregisteredEndpointIds) {
    should(delivered.includes(endpointId)).be.false();
  }
  for (const delivery of actual.deliveries) {
    should(delivery.responseStatus).equal(200);
    should(delivery.address.length > 0).be.true();
  }
};

describe('Mercury black-box SIT', () => {
  let stack: MercuryTestStack;

  beforeAll(async () => {
    stack = await loadMercuryTestStack();
  });

  afterAll(async () => {
    if (stack !== undefined) {
      await stack.close();
    }
  });

  it('requires distinct real dependency claims', async () => {
    // Arrange
    const expectedMinimumLandscapes = 2;

    // Act
    const actual = await stack.inspectDependencies();

    // Assert
    for (const claim of [actual.neon, actual.tigris, actual.secretStore, actual.route53, actual.observability]) {
      should(claim.implementation).equal('real');
      should(claim.reachable).be.true();
      should(claim.claimName.length > 0).be.true();
      should(claim.identity.length > 0).be.true();
    }
    should(actual.tigris.readAfterWriteVerified).be.true();
    should(actual.secretStore.externalSecretsReady).be.true();
    should(actual.upstash.length >= expectedMinimumLandscapes).be.true();
    should(new Set(actual.upstash.map(claim => claim.landscape)).size).equal(actual.upstash.length);
    should(new Set(actual.upstash.map(claim => claim.identity)).size).equal(actual.upstash.length);
    for (const claim of actual.upstash) {
      should(claim.implementation).equal('real');
      should(claim.reachable).be.true();
    }
  });

  it('verifies real and forged fixtures for all seven provider formats', async () => {
    // Arrange
    const expectedProviders = sorted(requiredProviderNames);

    // Act
    const actual = await stack.runProviderVerificationMatrix();

    // Assert
    should(sorted(actual.map(result => result.provider))).deepEqual(expectedProviders);
    should(actual).have.length(expectedProviders.length);
    for (const result of actual) {
      should(result.fixtureFormat.trim().length > 0).be.true();
      should(result.acceptedStatus).equal(200);
      should(result.acceptedEventDelta).equal(1);
      should(result.forgedStatus).equal(401);
      should(result.forgedEventDelta).equal(0);
    }
  });

  it('atomically deduplicates, persists, and enqueues before 200 and delayed delivery', async () => {
    // Arrange
    const expectedRetryAndDedupWindowMs = 72 * HOUR_MS;

    // Act
    const actual = await stack.runAtomicAcceptance();

    // Assert
    should(requiredProviderNames.includes(actual.provider)).be.true();
    should(actual.storedEventId.length > 0).be.true();
    should(actual.storedAcknowledgedAtMs <= actual.responseCompletedAtMs).be.true();
    should(actual.responseStatus).equal(200);
    should(actual.firstDeliveryStartedAtMs > actual.responseCompletedAtMs).be.true();
    should(sorted(actual.committedEndpointIds)).deepEqual(sorted(actual.registeredEndpointIds));
    should(actual.registeredEndpointIds.length > 0).be.true();
    should(actual.dedupExpiresAtMs - actual.storedAcknowledgedAtMs).be.within(
      expectedRetryAndDedupWindowMs - 1_000,
      expectedRetryAndDedupWindowMs + 1_000,
    );
    should(actual.duplicate.responseStatus).equal(200);
    should(actual.duplicate.eventDelta).equal(0);
    should(actual.duplicate.obligationDelta).equal(0);
    should(actual.duplicate.dedupExpiresAtMs).equal(actual.dedupExpiresAtMs);

    should(actual.otherLandscape.landscape).not.equal(actual.landingLandscape);
    should(actual.otherLandscape.responseStatus).equal(200);
    should(actual.otherLandscape.eventDelta).equal(1);
    should(actual.otherLandscape.obligationDelta).equal(actual.registeredEndpointIds.length);

    should(actual.failedCommit.responseStatus).be.within(500, 599);
    should(actual.failedCommit.dedupDelta).equal(0);
    should(actual.failedCommit.eventDelta).equal(0);
    should(actual.failedCommit.obligationDelta).equal(0);
  });

  it('fans to every registration while locality changes only the address', async () => {
    // Arrange
    const expectedSingleCardinality = 1;
    const expectedPerRowCardinality = 3;

    // Act
    const actual = await stack.runFanout();

    // Assert
    assertFanoutCase(actual.singleRegistration, expectedSingleCardinality);
    assertFanoutCase(actual.perRowRegistrations, expectedPerRowCardinality);
    const addressKinds = new Set(
      [...actual.singleRegistration.deliveries, ...actual.perRowRegistrations.deliveries].map(
        delivery => delivery.addressKind,
      ),
    );
    should(addressKinds.has('local')).be.true();
    should(addressKinds.has('canonical')).be.true();
  });

  it('freshly signs initial, retry, and replay attempts and rejects invalid signatures on both paths', async () => {
    // Arrange
    const expectedKinds = ['initial', 'replay', 'retry'];
    const expectedRejected = [
      'cluster-local:forged',
      'cluster-local:stale',
      'cluster-local:stripped',
      'public:forged',
      'public:stale',
      'public:stripped',
    ];

    // Act
    const actual = await stack.runSignatureLifecycle();

    // Assert
    should(sorted(actual.attempts.map(attempt => attempt.kind))).deepEqual(expectedKinds);
    should(actual.attempts).have.length(3);
    should(actual.attempts.map(attempt => attempt.attempt)).deepEqual([1, 2, 3]);
    should(actual.attempts.map(attempt => attempt.replay)).deepEqual([false, false, true]);
    should(new Set(actual.attempts.map(attempt => attempt.signatureHeader)).size).equal(3);
    should(new Set(actual.attempts.map(attempt => attempt.rawBodyBase64)).size).equal(1);
    should(actual.attempts.map(attempt => attempt.consumerStatus)).deepEqual([503, 200, 200]);
    for (const attempt of actual.attempts) {
      should(attempt.signatureHeader).match(/^t=\d+,\s*v1=[a-f\d]{64}$/);
    }
    for (let index = 1; index < actual.attempts.length; index += 1) {
      const previous = actual.attempts[index - 1];
      const current = actual.attempts[index];
      should(previous !== undefined && current !== undefined).be.true();
      should(current?.timestampSeconds !== undefined && previous?.timestampSeconds !== undefined).be.true();
      should((current?.timestampSeconds ?? 0) > (previous?.timestampSeconds ?? 0)).be.true();
    }

    should(sorted(actual.rejected.map(result => `${result.path}:${result.mutation}`))).deepEqual(expectedRejected);
    for (const result of actual.rejected) {
      should(result.consumerStatus).equal(401);
      should(result.handlerInvocationDelta).equal(0);
    }
  });

  it('logs into the console, fans in landscapes, and replays at the source landscape', async () => {
    // Arrange
    const expectedDefaultAccount = 'internal/default';

    // Act
    const actual = await stack.runConsoleJourney();

    // Assert
    should(actual.loginStatus).equal(200);
    should(actual.accountName).equal(expectedDefaultAccount);
    should(new Set(actual.queriedLandscapes).size >= 2).be.true();
    should(sorted(actual.returnedSourceLandscapes)).deepEqual(sorted(actual.queriedLandscapes));
    should(actual.partialFailures).deepEqual([]);
    assertSuccessfulStatus(actual.replay.requestStatus);
    should(actual.replay.enqueuedLandscape).equal(actual.replay.sourceLandscape);
    should(actual.replay.endpointId.length > 0).be.true();
    should(actual.replay.replayFlag).be.true();
    should(actual.replay.freshSignatureAccepted).be.true();
    should(actual.replay.auditRecorded).be.true();
    should(actual.preview.gate).equal('D11');
    should(actual.preview.routeStateVisible).be.true();
    should(actual.preview.callbackDeliveryVisible).be.false();
  });

  it('runs Apple backfill once through the ordinary pipeline and alerts on missed cycles', async () => {
    // Arrange
    const firstAlertingMissedCycleCount = 3;

    // Act
    const actual = await stack.runAppleBackfill();

    // Assert
    should(actual.competingReplicaCount >= 2).be.true();
    should(actual.leaseWinnerCount).equal(1);
    should(actual.fetchedNotificationCount > 0).be.true();
    should(actual.acceptedOrDuplicateCount).equal(actual.fetchedNotificationCount);
    should(actual.ordinaryPipelineCount).equal(actual.fetchedNotificationCount);
    should(actual.cursorPersistedAfterAcceptance).be.true();
    should(actual.consecutiveMissedCycles >= firstAlertingMissedCycleCount).be.true();
    should(actual.missedCycleAlertFired).be.true();
  });

  it('reconciles the Google subscription to 31-day retention and an explicit DLQ', async () => {
    // Arrange
    const expectedDriftDimensions = [
      'deadLetterPolicy',
      'messageRetention',
      'oidcAudience',
      'oidcServiceAccount',
      'pushEndpoint',
    ];

    // Act
    const actual = await stack.inspectGoogleSubscription();

    // Assert
    should(actual.messageRetentionDays).equal(31);
    should(actual.deadLetterPolicyExplicit).be.true();
    should(actual.deadLetterTopic.length > 0).be.true();
    should(actual.oidcServiceAccountEmail.length > 0).be.true();
    should(actual.oidcAudience).equal(actual.storedRegisteredUrl);
    should(sorted(actual.driftDetected)).deepEqual(expectedDriftDimensions);
    should(actual.driftReconciled).be.true();
  });

  it('archives before deletion and blocks deletion on archive failure', async () => {
    // Arrange
    const expectedFailureDeletionState = false;

    // Act
    const actual = await stack.runArchiveLifecycle();

    // Assert
    should(actual.success.uploadedAtMs <= actual.success.verifiedAtMs).be.true();
    should(actual.success.verifiedAtMs < actual.success.deletedAtMs).be.true();
    should(actual.success.checksumVerified).be.true();
    should(actual.success.liveStreamDeleted).be.true();
    should(actual.failure.alertFired).be.true();
    should(actual.failure.deletionBlocked).be.true();
    should(actual.failure.liveStreamPresent).be.true();
    should(actual.failure.liveStreamDeleted).equal(expectedFailureDeletionState);
  });

  it('lands through valid Route 53 geoproximity metadata', async () => {
    // Arrange
    const coordinatePattern = /^-?\d+(?:\.\d{1,2})?$/;

    // Act
    const actual = await stack.inspectRoute53Landing();

    // Assert
    should(actual.recordName).startWith('hooks.webhook.mercury.');
    should(actual.recordName).endWith('.cluster.atomi.cloud');
    should(actual.providerResponseStatus).equal(200);
    should(new Set(actual.zones).size >= 2).be.true();
    should(actual.sets.length >= 2).be.true();
    should(new Set(actual.sets.map(record => record.setIdentifier)).size).equal(actual.sets.length);
    should(actual.sets.some(record => record.setIdentifier === actual.observedSetIdentifier)).be.true();
    should(actual.emptyUnhealthySetDeleted).be.true();
    should(actual.mixedPolicyTypes).be.false();
    for (const record of actual.sets) {
      should(record.policy).equal('geoproximity');
      should(record.coordinates.latitude).match(coordinatePattern);
      should(record.coordinates.longitude).match(coordinatePattern);
      should(Number(record.coordinates.latitude)).be.within(-90, 90);
      should(Number(record.coordinates.longitude)).be.within(-180, 180);
      should(Number.isInteger(record.bias)).be.true();
      should(record.bias).be.within(-99, 99);
      should(record.ttlSeconds).equal(60);
      should(record.healthyIngressAddresses.length > 0).be.true();
    }
  });
});
