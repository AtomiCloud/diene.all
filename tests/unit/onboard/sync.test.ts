import { describe, it } from 'bun:test';
import type { Problem } from '@atomicloud/diene.problems';
import { Ok, type Result } from '@atomicloud/diene.result';
import { Temporal } from '@js-temporal/polyfill';
import should from 'should';
import { createSingleFlightCache } from '../../../src/lib/cache';
import { createOnboardSync, type OnboardBackendBinding } from '../../../src/lib/onboard/sync';
import type { TokenResponse } from '../../../src/lib/provider';
import {
  type BackendRegistration,
  type CanonicalResourceKey,
  createResourceTree,
  type ResourceKey,
} from '../../../src/lib/resource-tree';
import { type AuthState, authed, type TokenSet } from '../../../src/lib/retriever';
import { buildTokenSet } from '../../../src/test-helper/builders';
import { FakeOnboardingBackendApi, InMemoryOnboardSyncState } from '../../../src/test-helper/fake-phases';
import { FakeAuthProvider } from '../../../src/test-helper/fake-provider';
import { FakeAuthStateRetriever } from '../../../src/test-helper/fake-retrievers';
import { InMemorySingleFlightCoordinator } from '../../../src/test-helper/fake-single-flight-coordinator';
import { InMemoryTokenCacheStore } from '../../../src/test-helper/fake-token-cache-store';
import { authProblems, testProblem } from '../support';

const NOW = Temporal.Instant.from('2026-07-24T12:00:00Z');
const ZINC_KEY = 'alcohol/lapras/zinc/api' as CanonicalResourceKey;
const ARGON_KEY = 'alcohol/lapras/argon/api' as CanonicalResourceKey;
const PROBLEMS = authProblems().problems;

const zinc: ResourceKey = {
  platform: 'alcohol',
  landscape: 'lapras',
  service: 'zinc',
  resourceName: 'api',
};
const argon: ResourceKey = {
  platform: 'alcohol',
  landscape: 'lapras',
  service: 'argon',
  resourceName: 'api',
};

function registration(
  backendId: string,
  resources: readonly ResourceKey[],
  onboardingResource = resources[0] as ResourceKey,
): BackendRegistration {
  return { backendId, resources, onboardingResource };
}

function tokenSet(
  zincClaims: Readonly<Record<string, unknown>> = {},
  argonClaims?: Readonly<Record<string, unknown>>,
): TokenSet {
  return buildTokenSet({
    accessTokenClaims: {
      [ZINC_KEY]: zincClaims,
      ...(argonClaims === undefined ? {} : { [ARGON_KEY]: argonClaims }),
    },
  });
}

async function resourceTree(bindings: readonly BackendRegistration[]) {
  const clock = { now: () => NOW };
  const tokenCache = await createSingleFlightCache<CanonicalResourceKey, TokenResponse>({
    coordinator: new InMemorySingleFlightCoordinator(),
    clock,
    skew: Temporal.Duration.from({ seconds: 0 }),
  }).unwrap();
  return createResourceTree(new FakeAuthProvider(), {
    bindings,
    store: new InMemoryTokenCacheStore(),
    tokenCache,
    clock,
    problems: PROBLEMS,
    skew: Temporal.Duration.from({ seconds: 0 }),
  }).unwrap();
}

interface SyncHarnessOptions {
  readonly registrations?: readonly BackendRegistration[];
  readonly bindings?: readonly OnboardBackendBinding[];
  readonly retriever?: FakeAuthStateRetriever;
  readonly initial?: TokenSet;
}

async function syncHarness(options: SyncHarnessOptions = {}) {
  const registrations = options.registrations ?? [registration('zinc', [zinc])];
  const tree = await resourceTree(registrations);
  const api = new FakeOnboardingBackendApi();
  const state = new InMemoryOnboardSyncState();
  const retriever = options.retriever ?? new FakeAuthStateRetriever({ tokenSet: options.initial ?? tokenSet() });
  const bindings = options.bindings ?? [{ backendId: 'zinc', api }];
  const subject = await createOnboardSync({
    retriever,
    resourceTree: tree,
    state,
    bindings,
    problems: PROBLEMS,
  }).unwrap();
  return { subject, api, state, retriever, tree };
}

class GatedRetriever extends FakeAuthStateRetriever {
  readonly gated: Promise<AuthState<TokenSet>>;
  release!: () => void;

  constructor(value: TokenSet) {
    super({ tokenSet: value });
    this.gated = new Promise(resolve => {
      this.release = () => resolve(authed(value));
    });
  }

  override getTokenSet(): Result<AuthState<TokenSet>, Problem> {
    this.getTokenSetCalls += 1;
    return Ok(this.gated);
  }
}

describe('OnboardSync construction', () => {
  it('is ready with validated immutable bindings and no temporal registration step', async () => {
    // Arrange
    const tree = await resourceTree([registration('zinc', [zinc])]);
    const api = new FakeOnboardingBackendApi();
    const state = new InMemoryOnboardSyncState();
    const mutableBinding = { backendId: 'zinc', api, applicationClaim: 'configuration_id' };

    // Act
    const subject = await createOnboardSync({
      retriever: new FakeAuthStateRetriever({ tokenSet: tokenSet({ alcohol_zinc: 'true' }) }),
      resourceTree: tree,
      state,
      bindings: [mutableBinding],
      problems: PROBLEMS,
    }).unwrap();
    mutableBinding.backendId = 'argon';
    const phase = await subject.phase('zinc').unwrap();
    const phases = subject.phases();

    // Assert
    should(phase.kind).equal('bootstrapping');
    should(phases.zinc?.kind).equal('bootstrapping');
    should(phases.argon).be.undefined();
    should(Object.isFrozen(phases)).be.true();
  });

  it('returns Problems without throwing for invalid, duplicate, or unregistered bindings', async () => {
    // Arrange
    const mapped = testProblem('invalid onboarding binding');
    const tree = await resourceTree([registration('zinc', [zinc])]);
    const api = new FakeOnboardingBackendApi();
    const base = {
      retriever: new FakeAuthStateRetriever({ tokenSet: tokenSet() }),
      resourceTree: tree,
      state: new InMemoryOnboardSyncState(),
      problems: PROBLEMS,
      mapError: () => mapped,
    };
    const inputs = [
      [{ backendId: 'UPPER', api }],
      [{ backendId: 'zinc', api, applicationClaim: '   ' }],
      [
        { backendId: 'zinc', api },
        { backendId: 'zinc', api },
      ],
      [{ backendId: 'argon', api }],
      [{ backendId: 'zinc', api, applicationClaim: { name: 'configuration_id', resource: argon } }],
    ];

    // Act
    const results = inputs.map(bindings => () => createOnboardSync({ ...base, bindings }));
    const missingOptions = createOnboardSync({});

    // Assert
    for (const result of results) {
      should(result).not.throw();
      should(await result().isErr()).be.true();
    }
    should((await missingOptions.unwrapErr()).title).equal('Backend onboarding failed');
  });

  it('returns Problems for malformed and unknown public backend values', async () => {
    // Arrange
    const { subject } = await syncHarness();

    // Act
    const malformedPhase = subject.phase('UPPER');
    const unknownPhase = subject.phase('argon');
    const malformedSync = subject.syncBackend('UPPER');
    const unknownSync = subject.syncBackend('argon');
    const malformedTraffic = subject.reportTrafficFailure('zinc', 99);

    // Assert
    should(await malformedPhase.isErr()).be.true();
    should(await unknownPhase.isErr()).be.true();
    should(await malformedSync.isErr()).be.true();
    should(await unknownSync.isErr()).be.true();
    should(await malformedTraffic.isErr()).be.true();
  });
});

describe('OnboardSync phase machine', () => {
  it('takes the exact registration-claim fast path without backend calls', async () => {
    // Arrange
    const retriever = new FakeAuthStateRetriever({
      tokenSet: tokenSet({ alcohol_zinc: 'true', configuration_id: 'cfg-1' }),
    });
    const api = new FakeOnboardingBackendApi();
    const { subject } = await syncHarness({
      retriever,
      bindings: [{ backendId: 'zinc', api, applicationClaim: 'configuration_id' }],
    });

    // Act
    const actual = await subject.syncBackend('zinc').unwrap();

    // Assert
    should(actual.kind).equal('ready');
    should(api.getMeCalls).have.length(0);
    should(api.createUserCalls).have.length(0);
    should(retriever.forceTokenSetCalls).equal(0);
  });

  it('enters needsOnboarding when registration is complete but an application claim is absent', async () => {
    // Arrange
    const api = new FakeOnboardingBackendApi();
    const { subject } = await syncHarness({
      initial: tokenSet({ alcohol_zinc: 'true' }),
      bindings: [{ backendId: 'zinc', api, applicationClaim: 'configuration_id' }],
    });

    // Act
    const first = await subject.syncBackend('zinc').unwrap();
    const second = await subject.syncBackend('zinc').unwrap();

    // Assert
    should(first.kind).equal('needsOnboarding');
    should(second.kind).equal('needsOnboarding');
    should(api.getMeCalls).have.length(0);
  });

  it('can scope an application claim requirement to one validated backend resource', async () => {
    // Arrange
    const api = new FakeOnboardingBackendApi();
    const { subject } = await syncHarness({
      registrations: [registration('multi', [zinc, argon], zinc)],
      initial: tokenSet({ alcohol_zinc: 'true', configuration_id: 'cfg-1' }, { alcohol_argon: 'true' }),
      bindings: [
        {
          backendId: 'multi',
          api,
          applicationClaim: { name: 'configuration_id', resource: zinc },
        },
      ],
    });

    // Act
    const actual = await subject.syncBackend('multi').unwrap();

    // Assert
    should(actual.kind).equal('ready');
  });

  it('skips create after a 200 lookup, refreshes every token, and becomes ready', async () => {
    // Arrange
    const api = new FakeOnboardingBackendApi({ getMe: [200] });
    const retriever = new FakeAuthStateRetriever({ tokenSet: tokenSet() });
    retriever.enqueueForced(tokenSet({ alcohol_zinc: 'true' }));
    const { subject } = await syncHarness({ retriever, bindings: [{ backendId: 'zinc', api }] });

    // Act
    const actual = await subject.syncBackend('zinc').unwrap();

    // Assert
    should(actual.kind).equal('ready');
    should(api.getMeCalls).have.length(1);
    should(api.createUserCalls).have.length(0);
    should(retriever.forceTokenSetCalls).equal(1);
  });

  it('creates after a 404 with raw tokens and a bearer header, then refreshes', async () => {
    // Arrange
    const api = new FakeOnboardingBackendApi({ getMe: [404], create: [201] });
    const initial = tokenSet();
    const retriever = new FakeAuthStateRetriever({ tokenSet: initial });
    retriever.enqueueForced(tokenSet({ alcohol_zinc: 'true' }));
    const { subject } = await syncHarness({ retriever, bindings: [{ backendId: 'zinc', api }] });

    // Act
    const actual = await subject.syncBackend('zinc').unwrap();
    const request = api.createUserCalls[0];

    // Assert
    should(actual.kind).equal('ready');
    should(request?.idToken).equal(initial.idToken);
    should(request?.accessToken).equal(initial.accessTokens[ZINC_KEY]);
    should(request?.authorization).equal(`Bearer ${initial.accessTokens[ZINC_KEY]}`);
  });

  it('treats a 409 create response as create-or-ok success', async () => {
    // Arrange
    const api = new FakeOnboardingBackendApi({ getMe: [404], create: [409] });
    const retriever = new FakeAuthStateRetriever({ tokenSet: tokenSet() });
    retriever.enqueueForced(tokenSet({ alcohol_zinc: 'true' }));
    const { subject } = await syncHarness({ retriever, bindings: [{ backendId: 'zinc', api }] });

    // Act
    const actual = await subject.syncBackend('zinc').unwrap();

    // Assert
    should(actual.kind).equal('ready');
    should(api.createUserCalls).have.length(1);
  });

  it('returns the registered 409 OnboardingClaimMissing Problem when refresh cannot repair claims', async () => {
    // Arrange
    const api = new FakeOnboardingBackendApi({ getMe: [200] });
    const retriever = new FakeAuthStateRetriever({ tokenSet: tokenSet() });
    retriever.enqueueForced(tokenSet());
    const { subject } = await syncHarness({ retriever, bindings: [{ backendId: 'zinc', api }] });

    // Act
    const actual = await subject.syncBackend('zinc').unwrapErr();
    const phase = await subject.phase('zinc').unwrap();

    // Assert
    should(actual.status).equal(409);
    should(actual.type).equal(PROBLEMS.OnboardingClaimMissing.type);
    should(phase.kind).equal('error');
  });

  it('fails closed for unauthenticated and malformed token sets before backend calls', async () => {
    // Arrange
    const unauthenticated = new FakeAuthStateRetriever({ authenticated: false, tokenSet: tokenSet() });
    const malformed = new FakeAuthStateRetriever({
      tokenSet: { idToken: 'not-a-jwt', accessTokens: { [ZINC_KEY]: 'not-a-jwt' } },
    });
    const unauthenticatedApi = new FakeOnboardingBackendApi();
    const malformedApi = new FakeOnboardingBackendApi();
    const unauthenticatedSubject = (
      await syncHarness({
        retriever: unauthenticated,
        bindings: [{ backendId: 'zinc', api: unauthenticatedApi }],
      })
    ).subject;
    const malformedSubject = (
      await syncHarness({ retriever: malformed, bindings: [{ backendId: 'zinc', api: malformedApi }] })
    ).subject;

    // Act
    const unauthenticatedResult = unauthenticatedSubject.syncBackend('zinc');
    const malformedResult = malformedSubject.syncBackend('zinc');

    // Assert
    should((await unauthenticatedResult.unwrapErr()).status).equal(401);
    should(await malformedResult.isErr()).be.true();
    should(unauthenticatedApi.getMeCalls).have.length(0);
    should(malformedApi.getMeCalls).have.length(0);
  });

  it('maps unexpected lookup/create statuses and adapter failures to independent error phases', async () => {
    // Arrange
    const lookupApi = new FakeOnboardingBackendApi({ getMe: [500] });
    const createApi = new FakeOnboardingBackendApi({ getMe: [404], create: [500] });
    const adapterFailure = testProblem('lookup adapter failed');
    const failedApi = new FakeOnboardingBackendApi({ getMe: [adapterFailure] });
    const lookupSubject = (await syncHarness({ bindings: [{ backendId: 'zinc', api: lookupApi }] })).subject;
    const createSubject = (await syncHarness({ bindings: [{ backendId: 'zinc', api: createApi }] })).subject;
    const failedSubject = (await syncHarness({ bindings: [{ backendId: 'zinc', api: failedApi }] })).subject;

    // Act
    const lookup = lookupSubject.syncBackend('zinc');
    const create = createSubject.syncBackend('zinc');
    const failed = failedSubject.syncBackend('zinc');

    // Assert
    should(await lookup.isErr()).be.true();
    should(await create.isErr()).be.true();
    should(await failed.unwrapErr()).equal(adapterFailure);
  });
});

describe('OnboardSync keyed coordination', () => {
  it('shares one per-backend flight across concurrent sync callers', async () => {
    // Arrange
    const retriever = new GatedRetriever(tokenSet({ alcohol_zinc: 'true' }));
    const api = new FakeOnboardingBackendApi();
    const { subject, state } = await syncHarness({
      retriever,
      bindings: [{ backendId: 'zinc', api }],
    });

    // Act
    const first = subject.syncBackend('zinc');
    const second = subject.syncBackend('zinc');
    const flightWasRegistered = state.flightValues.has('zinc');
    retriever.release();
    const actual = await Promise.all([first.unwrap(), second.unwrap()]);

    // Assert
    should(flightWasRegistered).be.true();
    should(actual.map(phase => phase.kind)).deepEqual(['ready', 'ready']);
    should(retriever.getTokenSetCalls).equal(1);
    should(state.flightValues.has('zinc')).be.false();
  });

  it('keeps ready and error phases isolated per backend', async () => {
    // Arrange
    const zincApi = new FakeOnboardingBackendApi();
    const argonFailure = testProblem('argon failed');
    const argonApi = new FakeOnboardingBackendApi({ getMe: [argonFailure] });
    const retriever = new FakeAuthStateRetriever({
      tokenSet: tokenSet({ alcohol_zinc: 'true' }, {}),
    });
    const { subject } = await syncHarness({
      registrations: [registration('zinc', [zinc]), registration('argon', [argon], argon)],
      retriever,
      bindings: [
        { backendId: 'zinc', api: zincApi },
        { backendId: 'argon', api: argonApi },
      ],
    });

    // Act
    const zincPhase = await subject.syncBackend('zinc').unwrap();
    const argonResult = subject.syncBackend('argon');
    const argonProblem = await argonResult.unwrapErr();
    const phases = subject.phases();

    // Assert
    should(zincPhase.kind).equal('ready');
    should(argonProblem).equal(argonFailure);
    should(phases.zinc?.kind).equal('ready');
    should(phases.argon?.kind).equal('error');
  });

  it('turns later 401/404 traffic into terminal errors without re-running onboarding', async () => {
    // Arrange
    const api = new FakeOnboardingBackendApi();
    const { subject } = await syncHarness({
      initial: tokenSet({ alcohol_zinc: 'true' }),
      bindings: [{ backendId: 'zinc', api }],
    });
    await subject.syncBackend('zinc').unwrap();
    const before = subject.reportTrafficFailure('zinc', 200);

    // Act
    const preserved = await before.unwrap();
    const failed = await subject.reportTrafficFailure('zinc', 401).unwrap();
    const later = subject.syncBackend('zinc');

    // Assert
    should(preserved.kind).equal('ready');
    should(failed.kind).equal('error');
    should(await later.isErr()).be.true();
    should(api.getMeCalls).have.length(0);
    should(api.createUserCalls).have.length(0);
  });
});
