import { describe, it } from 'bun:test';
import type { Problem } from '@atomicloud/diene.problems';
import { Ok } from '@atomicloud/diene.result';
import should from 'should';
import type { BackendPhase, CreateUserRequest, OnboardSync } from '../../src/lib/onboard/sync';
import {
  driveBackendPhase,
  expectPhase,
  FakeOnboardingBackendApi,
  InMemoryOnboardSyncState,
  PhaseAssertionError,
} from '../../src/test-helper';

const READY = Object.freeze({ kind: 'ready' } as const);
const NEEDS_ONBOARDING = Object.freeze({ kind: 'needsOnboarding' } as const);

function phaseProblem(): Problem {
  return {
    type: 'about:blank',
    title: 'Onboarding failure',
    status: 502,
    detail: 'The fake onboarding API was instructed to fail.',
    data: {},
  };
}

function createRequest(accessToken: string): CreateUserRequest {
  return {
    idToken: 'id-token',
    accessToken,
    authorization: `Bearer ${accessToken}`,
  };
}

function syncReturning(phase: BackendPhase, syncCalls: unknown[], phaseCalls: unknown[]): OnboardSync {
  return {
    phase: backendId => {
      phaseCalls.push(backendId);
      return Ok(phase);
    },
    phases: () => ({ zinc: phase }),
    syncBackend: backendId => {
      syncCalls.push(backendId);
      return Ok(phase);
    },
    reportTrafficFailure: () => Ok(phase),
  };
}

describe('FakeOnboardingBackendApi', () => {
  it('returns default and scripted statuses, Problems, and exhausted fallbacks', async () => {
    // Arrange
    const problem = phaseProblem();
    const defaults = new FakeOnboardingBackendApi();
    const subject = new FakeOnboardingBackendApi({
      getMe: [204, problem],
      create: [201, problem],
    });
    const request = createRequest('access-token');

    // Act
    const defaultGet = await defaults.getMe('default-access').serial();
    const defaultCreate = await defaults.createUser(createRequest('default-access')).serial();
    const getStatus = await subject.getMe('access-token').serial();
    const getProblem = await subject.getMe('second-token').serial();
    const getFallback = await subject.getMe('third-token').serial();
    const createStatus = await subject.createUser(request).serial();
    const createProblem = await subject.createUser(request).serial();
    const createFallback = await subject.createUser(request).serial();

    // Assert
    should(defaultGet).deepEqual(['ok', { status: 200 }]);
    should(defaultCreate).deepEqual(['ok', { status: 201 }]);
    should(getStatus).deepEqual(['ok', { status: 204 }]);
    should(getProblem).deepEqual(['err', problem]);
    should(getFallback).deepEqual(['ok', { status: 500 }]);
    should(createStatus).deepEqual(['ok', { status: 201 }]);
    should(createProblem).deepEqual(['err', problem]);
    should(createFallback).deepEqual(['ok', { status: 500 }]);
    should(subject.getMeCalls).deepEqual(['access-token', 'second-token', 'third-token']);
    should(subject.createUserCalls).deepEqual([request, request, request]);
  });
});

describe('InMemoryOnboardSyncState', () => {
  it('keeps phase and flight state isolated per backend', async () => {
    // Arrange
    const subject = new InMemoryOnboardSyncState();
    const errorPhase: BackendPhase = { kind: 'error', problem: phaseProblem() };
    const zincFlight = Ok<BackendPhase, Problem>(READY).serial();
    const tinFlight = Ok<BackendPhase, Problem>(errorPhase).serial();

    // Act
    subject.setPhase('zinc', READY);
    subject.setPhase('tin', errorPhase);
    subject.setFlight('zinc', zincFlight);
    subject.setFlight('tin', tinFlight);
    subject.deleteFlight('zinc', tinFlight);
    const retainedZincFlight = subject.getFlight('zinc');
    subject.deleteFlight('zinc', zincFlight);
    const phases = {
      zinc: subject.getPhase('zinc'),
      tin: subject.getPhase('tin'),
      missing: subject.getPhase('missing'),
    };
    const flights = {
      zinc: subject.getFlight('zinc'),
      tin: subject.getFlight('tin'),
      missing: subject.getFlight('missing'),
    };

    // Assert
    should(retainedZincFlight).equal(zincFlight);
    should(phases.zinc).equal(READY);
    should(phases.tin).equal(errorPhase);
    should(phases.missing).be.undefined();
    should(flights.zinc).be.undefined();
    should(flights.tin).equal(tinFlight);
    should(flights.missing).be.undefined();
    should(subject.phaseValues.size).equal(2);
    should(subject.flightValues.size).equal(1);
    should(await tinFlight).deepEqual(['ok', errorPhase]);
  });
});

describe('phase assertion helpers', () => {
  it('returns the phase when expectPhase receives the expected kind', () => {
    // Arrange
    const phase = READY;

    // Act
    const actual = expectPhase(phase, 'ready');

    // Assert
    should(actual).equal(phase);
  });

  it('throws an inspectable assertion error for mismatched and absent phases', () => {
    // Arrange
    let mismatch: unknown;
    let absent: unknown;

    // Act
    try {
      expectPhase(NEEDS_ONBOARDING, 'ready');
    } catch (error: unknown) {
      mismatch = error;
    }
    try {
      expectPhase(undefined, 'ready');
    } catch (error: unknown) {
      absent = error;
    }

    // Assert
    should(mismatch instanceof PhaseAssertionError).be.true();
    should(absent instanceof PhaseAssertionError).be.true();
    if (mismatch instanceof PhaseAssertionError) {
      should(mismatch.name).equal('PhaseAssertionError');
      should(mismatch.expected).equal('ready');
      should(mismatch.actual).equal('needsOnboarding');
      should(mismatch.message).containEql('needsOnboarding');
    }
    if (absent instanceof PhaseAssertionError) {
      should(absent.actual).be.undefined();
      should(absent.message).containEql('undefined');
    }
  });

  it('drives a backend through sync and returns the asserted phase', async () => {
    // Arrange
    const syncCalls: unknown[] = [];
    const phaseCalls: unknown[] = [];
    const sync = syncReturning(READY, syncCalls, phaseCalls);

    // Act
    const actual = await driveBackendPhase(sync, 'zinc', 'ready');

    // Assert
    should(actual).equal(READY);
    should(syncCalls).deepEqual(['zinc']);
    should(phaseCalls).deepEqual(['zinc']);
  });

  it('rejects when driveBackendPhase observes the wrong phase', async () => {
    // Arrange
    const sync = syncReturning(NEEDS_ONBOARDING, [], []);
    let thrown: unknown;

    // Act
    try {
      await driveBackendPhase(sync, 'zinc', 'ready');
    } catch (error: unknown) {
      thrown = error;
    }

    // Assert
    should(thrown instanceof PhaseAssertionError).be.true();
    if (thrown instanceof PhaseAssertionError) {
      should(thrown.expected).equal('ready');
      should(thrown.actual).equal('needsOnboarding');
    }
  });
});
