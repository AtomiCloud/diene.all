import { describe, it } from 'bun:test';
import { Temporal } from '@js-temporal/polyfill';
import should from 'should';
import { authed, type TokenSet, unauthed } from '../../../src/lib/retriever';
import {
  ClientAuthStateRetriever,
  createClientAuthCache,
  defaultClientAuthEndpoints,
} from '../../../src/lib/retrievers/client';
import { buildTokenSet } from '../../../src/test-helper/builders';
import { FakeClock, testProblem } from '../support';
import { okBody, stubFetch } from './support';

const TOKENS_URL = defaultClientAuthEndpoints.tokenSet;
const FORCE_URL = defaultClientAuthEndpoints.forceTokenSet;
const CLAIMS_URL = defaultClientAuthEndpoints.claims;
const USER_URL = defaultClientAuthEndpoints.userInfo;

function nonExpiringState() {
  return authed(buildTokenSet({ idTokenClaims: { sub: 'user' } }));
}

describe('ClientAuthStateRetriever', () => {
  it('fetches the token set once and serves later reads from the injected cache', async () => {
    // Arrange
    const stub = stubFetch({ [TOKENS_URL]: okBody(nonExpiringState()) });
    const clock = new FakeClock(Temporal.Instant.fromEpochMilliseconds(0));
    const retriever = new ClientAuthStateRetriever({ fetch: stub.fetch, clock });

    // Act
    const first = await retriever.getTokenSet().unwrap();
    const second = await retriever.getTokenSet().unwrap();

    // Assert
    should(first.value.isAuthed).be.true();
    should(second.value.isAuthed).be.true();
    should(stub.calls[TOKENS_URL]).equal(1);
  });

  it('deduplicates concurrent token-set reads through the injected single-flight cell', async () => {
    // Arrange
    const stub = stubFetch({ [TOKENS_URL]: okBody(nonExpiringState()) });
    const retriever = new ClientAuthStateRetriever({
      fetch: stub.fetch,
      clock: new FakeClock(Temporal.Instant.fromEpochMilliseconds(0)),
    });

    // Act
    const results = await Promise.all([
      retriever.getTokenSet().serial(),
      retriever.getTokenSet().serial(),
      retriever.getTokenSet().serial(),
    ]);

    // Assert
    should(results.map(result => result[0])).deepEqual(['ok', 'ok', 'ok']);
    should(stub.calls[TOKENS_URL]).equal(1);
  });

  it('holds all state in the injected cache so a second retriever reuses it without fetching', async () => {
    // Arrange
    const stub = stubFetch({ [TOKENS_URL]: okBody(nonExpiringState()) });
    const cache = createClientAuthCache();
    const clock = new FakeClock(Temporal.Instant.fromEpochMilliseconds(0));
    const first = new ClientAuthStateRetriever({ fetch: stub.fetch, clock, cache });
    const second = new ClientAuthStateRetriever({ fetch: stub.fetch, clock, cache });

    // Act
    await first.getTokenSet().unwrap();
    const reused = await second.getTokenSet().unwrap();

    // Assert
    should(reused.value.isAuthed).be.true();
    should(stub.calls[TOKENS_URL]).equal(1);
  });

  it('refetches when the cached token set becomes stale against the injected clock', async () => {
    // Arrange
    const expiringState = authed(buildTokenSet({ idTokenClaims: { exp: 1_100 } }));
    const stub = stubFetch({ [TOKENS_URL]: okBody(expiringState) });
    const clock = new FakeClock(Temporal.Instant.fromEpochMilliseconds(1_000_000));
    const retriever = new ClientAuthStateRetriever({ fetch: stub.fetch, clock });

    // Act
    await retriever.getTokenSet().unwrap();
    clock.advance(Temporal.Duration.from({ seconds: 200 }));
    await retriever.getTokenSet().unwrap();

    // Assert
    should(stub.calls[TOKENS_URL]).equal(2);
  });

  it('forceTokenSet drops the cache and refetches from the force endpoint', async () => {
    // Arrange
    const stub = stubFetch({
      [TOKENS_URL]: okBody(nonExpiringState()),
      [FORCE_URL]: okBody(nonExpiringState()),
    });
    const clock = new FakeClock(Temporal.Instant.fromEpochMilliseconds(0));
    const retriever = new ClientAuthStateRetriever({ fetch: stub.fetch, clock });

    // Act
    await retriever.getTokenSet().unwrap();
    const forced = await retriever.forceTokenSet().unwrap();

    // Assert
    should(forced.value.isAuthed).be.true();
    should(stub.calls[FORCE_URL]).equal(1);
  });

  it('shares one force-token flight across concurrent callers', async () => {
    // Arrange
    const stub = stubFetch({ [FORCE_URL]: okBody(nonExpiringState()) });
    const retriever = new ClientAuthStateRetriever({
      fetch: stub.fetch,
      clock: new FakeClock(Temporal.Instant.fromEpochMilliseconds(0)),
    });

    // Act
    const results = await Promise.all([
      retriever.forceTokenSet().serial(),
      retriever.forceTokenSet().serial(),
      retriever.forceTokenSet().serial(),
    ]);

    // Assert
    should(results.map(result => result[0])).deepEqual(['ok', 'ok', 'ok']);
    should(stub.calls[FORCE_URL]).equal(1);
  });

  it('propagates a Problem body returned by the endpoint', async () => {
    // Arrange
    const stub = stubFetch({ [TOKENS_URL]: testProblem('boom', 502) });
    const clock = new FakeClock(Temporal.Instant.fromEpochMilliseconds(0));
    const retriever = new ClientAuthStateRetriever({ fetch: stub.fetch, clock });

    // Act
    const result = retriever.getTokenSet();

    // Assert
    should(await result.isErr()).be.true();
    should((await result.unwrapErr()).status).equal(502);
  });

  it('propagates a malformed-token failure surfaced by the refresh check', async () => {
    // Arrange
    const brokenState = authed({ idToken: 'not-a-jwt', accessTokens: {} });
    const stub = stubFetch({ [TOKENS_URL]: okBody(brokenState) });
    const clock = new FakeClock(Temporal.Instant.fromEpochMilliseconds(0));
    const retriever = new ClientAuthStateRetriever({ fetch: stub.fetch, clock });

    // Act
    const result = retriever.getTokenSet();

    // Assert
    should(await result.isErr()).be.true();
    should((await result.unwrapErr()).status).equal(401);
  });

  it('retrieves claims and user info and composes a fully authenticated state', async () => {
    // Arrange
    const stub = stubFetch({
      [TOKENS_URL]: okBody(nonExpiringState()),
      [CLAIMS_URL]: okBody(authed({ sub: 'user' })),
      [USER_URL]: okBody(authed({ name: 'Test User' })),
    });
    const clock = new FakeClock(Temporal.Instant.fromEpochMilliseconds(0));
    const retriever = new ClientAuthStateRetriever({ fetch: stub.fetch, clock });

    // Act
    const claims = await retriever.getClaims().unwrap();
    const user = await retriever.getUserInfo().unwrap();
    const states = await retriever.getStates().unwrap();

    // Assert
    should(claims.value.isAuthed).be.true();
    should(user.value.isAuthed).be.true();
    should(states.value.isAuthed).be.true();
    if (states.value.isAuthed) {
      should(states.value.data.claims.sub).equal('user');
      should(states.value.data.user.name).equal('Test User');
    }
    should(stub.calls[CLAIMS_URL]).equal(1);
    should(stub.calls[USER_URL]).equal(1);
  });

  it('composes an unauthenticated state when any endpoint is unauthenticated', async () => {
    // Arrange
    const stub = stubFetch({
      [TOKENS_URL]: okBody(unauthed<TokenSet>()),
      [CLAIMS_URL]: okBody(authed({ sub: 'user' })),
      [USER_URL]: okBody(authed({ name: 'Test User' })),
    });
    const retriever = new ClientAuthStateRetriever({
      fetch: stub.fetch,
      clock: new FakeClock(Temporal.Instant.fromEpochMilliseconds(0)),
    });

    // Act
    const actual = await retriever.getStates().unwrap();

    // Assert
    should(actual.value.isAuthed).be.false();
  });

  it('propagates an aggregate endpoint failure from getStates', async () => {
    // Arrange
    const stub = stubFetch({
      [TOKENS_URL]: okBody(nonExpiringState()),
      [CLAIMS_URL]: { malformed: true },
      [USER_URL]: okBody(authed({ name: 'Test User' })),
    });
    const retriever = new ClientAuthStateRetriever({
      fetch: stub.fetch,
      clock: new FakeClock(Temporal.Instant.fromEpochMilliseconds(0)),
    });

    // Act
    const actual = await retriever.getStates().unwrapErr();

    // Assert
    should(actual.status).equal(502);
    should(actual.detail).containEql('Invalid auth-state response');
  });

  it('clears the claims and user caches when forcing a token set', async () => {
    // Arrange
    const stub = stubFetch({
      [CLAIMS_URL]: okBody(authed({ sub: 'user' })),
      [USER_URL]: okBody(authed({ sub: 'user' })),
      [FORCE_URL]: okBody(nonExpiringState()),
    });
    const retriever = new ClientAuthStateRetriever({
      fetch: stub.fetch,
      clock: new FakeClock(Temporal.Instant.fromEpochMilliseconds(0)),
    });

    // Act
    await retriever.getClaims().unwrap();
    await retriever.getUserInfo().unwrap();
    await retriever.forceTokenSet().unwrap();
    await retriever.getClaims().unwrap();
    await retriever.getUserInfo().unwrap();

    // Assert
    should(stub.calls[CLAIMS_URL]).equal(2);
    should(stub.calls[USER_URL]).equal(2);
    should(stub.calls[FORCE_URL]).equal(1);
  });

  it('rejects malformed endpoints and wire values before they enter the cache', async () => {
    // Arrange
    let invalidEndpointCalls = 0;
    const invalidEndpoint = new ClientAuthStateRetriever({
      endpoints: { tokenSet: 'javascript:alert(1)' },
      fetch: async () => {
        invalidEndpointCalls += 1;
        return Response.json(null);
      },
      clock: new FakeClock(Temporal.Instant.fromEpochMilliseconds(0)),
    });
    const malformed = new ClientAuthStateRetriever({
      fetch: stubFetch({ [TOKENS_URL]: ['ok', { __kind: 'authed', value: { isAuthed: true, data: {} } }] }).fetch,
      clock: new FakeClock(Temporal.Instant.fromEpochMilliseconds(0)),
    });

    // Act
    const endpointFailure = await invalidEndpoint.getTokenSet().unwrapErr();
    const wireFailure = await malformed.getTokenSet().unwrapErr();

    // Assert
    should(invalidEndpointCalls).equal(0);
    should(endpointFailure.status).equal(502);
    should(wireFailure.status).equal(502);
  });

  it('maps rejected and invalid-JSON fetches through the default problem mapper', async () => {
    // Arrange
    const rejected = new ClientAuthStateRetriever({
      fetch: async () => Promise.reject('offline'),
      clock: new FakeClock(Temporal.Instant.fromEpochMilliseconds(0)),
    });
    const invalidJson = new ClientAuthStateRetriever({
      fetch: async () => new Response('not-json'),
      clock: new FakeClock(Temporal.Instant.fromEpochMilliseconds(0)),
    });

    // Act
    const rejectedProblem = await rejected.getTokenSet().unwrapErr();
    const jsonProblem = await invalidJson.getTokenSet().unwrapErr();

    // Assert
    should(rejectedProblem.detail).equal('Authentication state could not be retrieved.');
    should(jsonProblem.status).equal(502);
  });
});
