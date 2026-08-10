import { describe, it } from 'bun:test';
import { Err } from '@atomicloud/diene.result';
import { Temporal } from '@js-temporal/polyfill';
import should from 'should';
import type { CanonicalResourceKey } from '../../../src/lib/resource-tree';
import { authed } from '../../../src/lib/retriever';
import { createServerAuthCoordinator, ServerAuthStateRetriever } from '../../../src/lib/retrievers/server';
import { buildUnsignedJwt } from '../../../src/test-helper/builders';
import { FakeAuthProvider } from '../../../src/test-helper/fake-provider';
import { FakeClock, testProblem } from '../support';
import { FakeSession } from './support';

const KEY = 'alcohol/lapras/argon/api' as CanonicalResourceKey;
const AUDIENCE = 'https://api.argon.alcohol.lapras.cluster.atomi.cloud';
const EXPIRES_AT = Temporal.Instant.fromEpochMilliseconds(9_999_999_000);

function providerWithTokens(): FakeAuthProvider {
  return new FakeAuthProvider({
    idToken: buildUnsignedJwt({ sub: 'user' }),
    accessTokens: { [AUDIENCE]: { token: buildUnsignedJwt({ scope: 'api' }), expiresAt: EXPIRES_AT } },
  });
}

function makeRetriever(provider: FakeAuthProvider, session = new FakeSession()) {
  const clock = new FakeClock(Temporal.Instant.fromEpochMilliseconds(0));
  const coordinator = createServerAuthCoordinator();
  const retriever = new ServerAuthStateRetriever({
    provider,
    session,
    resources: { [KEY]: AUDIENCE },
    clock,
    coordinator,
  });
  return { retriever, coordinator, clock };
}

describe('ServerAuthStateRetriever', () => {
  it('assembles the token set from the injected provider', async () => {
    // Arrange
    const provider = providerWithTokens();
    const { retriever } = makeRetriever(provider);

    // Act
    const state = await retriever.getTokenSet().unwrap();

    // Assert
    should(state.value.isAuthed).be.true();
    if (state.value.isAuthed) {
      should(state.value.data.accessTokens[KEY]).be.a.String();
    }
  });

  it('deduplicates concurrent refreshes into a single provider fetch (single-flight)', async () => {
    // Arrange
    const provider = providerWithTokens();
    const { retriever } = makeRetriever(provider);

    // Act
    const first = retriever.getTokenSet().serial();
    const second = retriever.getTokenSet().serial();
    await Promise.all([first, second]);

    // Assert
    should(provider.idTokenCalls).equal(1);
  });

  it('serves later reads from the injected coordinator without a second provider fetch', async () => {
    // Arrange
    const provider = providerWithTokens();
    const { retriever } = makeRetriever(provider);

    // Act
    await retriever.getTokenSet().unwrap();
    await retriever.getTokenSet().unwrap();

    // Assert
    should(provider.idTokenCalls).equal(1);
  });

  it('shares state through the injected coordinator across retriever instances', async () => {
    // Arrange
    const provider = providerWithTokens();
    const coordinator = createServerAuthCoordinator();
    const clock = new FakeClock(Temporal.Instant.fromEpochMilliseconds(0));
    const resources = { [KEY]: AUDIENCE };
    const first = new ServerAuthStateRetriever({ provider, session: new FakeSession(), resources, clock, coordinator });
    const second = new ServerAuthStateRetriever({
      provider,
      session: new FakeSession(),
      resources,
      clock,
      coordinator,
    });

    // Act
    await first.getTokenSet().unwrap();
    const reused = await second.getTokenSet().unwrap();

    // Assert
    should(reused.value.isAuthed).be.true();
    should(provider.idTokenCalls).equal(1);
  });

  it('forceTokenSet clears tokens, refreshes, and refetches', async () => {
    // Arrange
    const provider = providerWithTokens();
    const { retriever } = makeRetriever(provider);

    // Act
    const forced = await retriever.forceTokenSet().unwrap();

    // Assert
    should(forced.value.isAuthed).be.true();
    should(provider.clearTokenCalls).equal(1);
    should(provider.refreshCalls).equal(1);
  });

  it('shares one force-token flight across concurrent backend onboarding callers', async () => {
    // Arrange
    const provider = providerWithTokens();
    const { retriever } = makeRetriever(provider);

    // Act
    const results = await Promise.all([
      retriever.forceTokenSet().serial(),
      retriever.forceTokenSet().serial(),
      retriever.forceTokenSet().serial(),
    ]);
    await retriever.getTokenSet().unwrap();

    // Assert
    should(results.map(result => result[0])).deepEqual(['ok', 'ok', 'ok']);
    should(provider.clearTokenCalls).equal(1);
    should(provider.refreshCalls).equal(1);
    should(provider.idTokenCalls).equal(1);
    should(provider.accessTokenCalls).have.length(1);
  });

  it('returns an unauthed state when the session is not authenticated', async () => {
    // Arrange
    const provider = providerWithTokens();
    const { retriever } = makeRetriever(provider, new FakeSession({ authenticated: false }));

    // Act
    const state = await retriever.getTokenSet().unwrap();

    // Assert
    should(state.value.isAuthed).be.false();
    should(provider.idTokenCalls).equal(0);
  });

  it('propagates a provider access-token failure', async () => {
    // Arrange
    const provider = providerWithTokens();
    provider.enqueueAccessToken(AUDIENCE, testProblem('access denied', 403));
    const { retriever } = makeRetriever(provider);

    // Act
    const result = retriever.getTokenSet();

    // Assert
    should(await result.isErr()).be.true();
    should((await result.unwrapErr()).status).equal(403);
  });

  it('decodes claims from the id token and propagates a malformed id token as a typed failure', async () => {
    // Arrange
    const good = providerWithTokens();
    const goodRetriever = makeRetriever(good).retriever;
    const broken = new FakeAuthProvider({ idToken: 'not-a-jwt' });
    const brokenRetriever = makeRetriever(broken).retriever;

    // Act
    const claims = await goodRetriever.getClaims().unwrap();
    const failure = brokenRetriever.getClaims();

    // Assert
    should(claims.value.isAuthed).be.true();
    should(await failure.isErr()).be.true();
    should((await failure.unwrapErr()).status).equal(401);
  });

  it('retrieves user info and composes all authenticated states', async () => {
    // Arrange
    const provider = providerWithTokens();
    const session = new FakeSession({ userInfo: { name: 'Test User' } });
    const { retriever } = makeRetriever(provider, session);

    // Act
    const user = await retriever.getUserInfo().unwrap();
    const states = await retriever.getStates().unwrap();

    // Assert
    should(user.value.isAuthed).be.true();
    should(states.value.isAuthed).be.true();
    if (states.value.isAuthed) should(states.value.data.user.name).equal('Test User');
  });

  it('composes an unauthenticated aggregate state', async () => {
    // Arrange
    const provider = providerWithTokens();
    const { retriever } = makeRetriever(provider, new FakeSession({ authenticated: false }));

    // Act
    const actual = await retriever.getStates().unwrap();

    // Assert
    should(actual.value.isAuthed).be.false();
  });

  it('propagates an aggregate provider failure from getStates', async () => {
    // Arrange
    const provider = providerWithTokens();
    provider.enqueueAccessToken(AUDIENCE, testProblem('aggregate failure', 503));
    const { retriever } = makeRetriever(provider);

    // Act
    const actual = await retriever.getStates().unwrapErr();

    // Assert
    should(actual.status).equal(503);
  });

  it('rejects malformed resource configuration before provider calls', async () => {
    // Arrange
    const provider = providerWithTokens();
    const retriever = new ServerAuthStateRetriever({
      provider,
      session: new FakeSession(),
      resources: { 'not-a-canonical-key': AUDIENCE } as unknown as Readonly<Record<CanonicalResourceKey, string>>,
      clock: new FakeClock(Temporal.Instant.fromEpochMilliseconds(0)),
    });

    // Act
    const actual = await retriever.getTokenSet().unwrapErr();

    // Assert
    should(actual.status).equal(502);
    should(provider.idTokenCalls).equal(0);
  });

  it('rejects provider ID-token and access-token response failures', async () => {
    // Arrange
    const idFailureProvider = providerWithTokens();
    idFailureProvider.enqueueIdToken(testProblem('id failed', 401));
    const invalidIdProvider = new FakeAuthProvider({
      idToken: '',
      accessTokens: { [AUDIENCE]: { token: 'token', expiresAt: EXPIRES_AT } },
    });
    const invalidAccessProvider = new FakeAuthProvider({
      idToken: buildUnsignedJwt({ sub: 'user' }),
      accessTokens: { [AUDIENCE]: { token: '', expiresAt: EXPIRES_AT } },
    });

    // Act
    const idFailure = await makeRetriever(idFailureProvider).retriever.getTokenSet().unwrapErr();
    const invalidId = await makeRetriever(invalidIdProvider).retriever.getTokenSet().unwrapErr();
    const invalidAccess = await makeRetriever(invalidAccessProvider).retriever.getTokenSet().unwrapErr();

    // Assert
    should(idFailure.status).equal(401);
    should(invalidId.status).equal(502);
    should(invalidAccess.status).equal(502);
  });

  it('returns cached unauthenticated state without rechecking the provider', async () => {
    // Arrange
    const provider = providerWithTokens();
    const session = new FakeSession({ authenticated: false });
    const { retriever } = makeRetriever(provider, session);

    // Act
    await retriever.getTokenSet().unwrap();
    await retriever.getTokenSet().unwrap();

    // Assert
    should(session.isAuthenticatedCalls).equal(1);
    should(provider.idTokenCalls).equal(0);
  });

  it('refreshes a cached token set that expires against the injected clock', async () => {
    // Arrange
    const accessToken = buildUnsignedJwt({ exp: 100 });
    const provider = new FakeAuthProvider({
      idToken: buildUnsignedJwt({ sub: 'user' }),
      accessTokens: { [AUDIENCE]: { token: accessToken, expiresAt: EXPIRES_AT } },
    });
    const { retriever, clock } = makeRetriever(provider);

    // Act
    await retriever.getTokenSet().unwrap();
    clock.advance(Temporal.Duration.from({ seconds: 101 }));
    await retriever.getTokenSet().unwrap();

    // Assert
    should(provider.idTokenCalls).equal(2);
  });

  it('propagates malformed tokens already present in the injected coordinator', async () => {
    // Arrange
    const provider = providerWithTokens();
    const { retriever, coordinator } = makeRetriever(provider);
    coordinator.tokenSet.write(authed({ idToken: 'broken', accessTokens: {} }));

    // Act
    const actual = await retriever.getTokenSet().unwrapErr();

    // Assert
    should(actual.status).equal(401);
    should(provider.idTokenCalls).equal(0);
  });

  it('propagates clear and refresh failures while forcing tokens', async () => {
    // Arrange
    const clearProvider = providerWithTokens();
    clearProvider.enqueueClear(testProblem('clear failed', 500));
    const refreshProvider = providerWithTokens();
    refreshProvider.enqueueRefresh(testProblem('refresh failed', 502));

    // Act
    const clearFailure = await makeRetriever(clearProvider).retriever.forceTokenSet().unwrapErr();
    const refreshFailure = await makeRetriever(refreshProvider).retriever.forceTokenSet().unwrapErr();

    // Assert
    should(clearFailure.detail).equal('clear failed');
    should(clearProvider.refreshCalls).equal(0);
    should(refreshFailure.detail).equal('refresh failed');
  });

  it('maps session exceptions and user-info errors to Problems', async () => {
    // Arrange
    const provider = providerWithTokens();
    const throwing = new ServerAuthStateRetriever({
      provider,
      resources: { [KEY]: AUDIENCE },
      session: {
        isAuthenticated: () => {
          throw 'offline';
        },
        getUserInfo: () => Err(testProblem()),
      },
      clock: new FakeClock(Temporal.Instant.fromEpochMilliseconds(0)),
    });
    const failingUser = new ServerAuthStateRetriever({
      provider,
      resources: { [KEY]: AUDIENCE },
      session: {
        isAuthenticated: () => true,
        getUserInfo: () => Err(testProblem('user failed', 503)),
      },
      clock: new FakeClock(Temporal.Instant.fromEpochMilliseconds(0)),
    });

    // Act
    const thrown = await throwing.getTokenSet().unwrapErr();
    const userFailure = await failingUser.getUserInfo().unwrapErr();

    // Assert
    should(thrown.detail).equal('Authentication state could not be retrieved.');
    should(userFailure.status).equal(503);
  });
});
