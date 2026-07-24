import { describe, it } from 'bun:test';
import type { Problem } from '@atomicloud/diene.problems';
import { Temporal } from '@js-temporal/polyfill';
import should from 'should';
import type { SignInUrlOptions, TokenResponse } from '../../src/lib/provider';
import { FakeAuthProvider } from '../../src/test-helper';

const RESOURCE = 'https://api.zinc.alcohol.lapras.cluster.atomi.cloud';
const EXPIRY = Temporal.Instant.from('2026-07-24T12:10:00Z');

function token(value: string): TokenResponse {
  return { token: value, expiresAt: EXPIRY };
}

function problem(detail = 'scripted failure'): Problem {
  return {
    type: 'about:blank',
    title: 'Scripted failure',
    status: 500,
    detail,
    data: {},
  };
}

function signInOptions(): SignInUrlOptions {
  return {
    redirectUri: 'https://app.invalid/callback',
    state: 'state',
    codeChallenge: 'challenge',
  };
}

describe('FakeAuthProvider', () => {
  it('implements fail-safe defaults across the AuthProvider seam', async () => {
    // Arrange
    const subject = new FakeAuthProvider();
    const options = signInOptions();

    // Act
    const access = await subject.getAccessToken(RESOURCE).serial();
    const idToken = await subject.getIdToken().serial();
    const refresh = await subject.refresh().serial();
    const clear = await subject.clearTokens().serial();
    const signIn = await subject.signInUrl(options).serial();

    // Assert
    should(access[0]).equal('err');
    should(idToken).deepEqual(['ok', '']);
    should(refresh[0]).equal('ok');
    should(clear[0]).equal('ok');
    should(signIn).deepEqual(['ok', 'https://identity.invalid/oidc/auth']);
    should(subject.accessTokenCalls).deepEqual([RESOURCE]);
    should(subject.idTokenCalls).equal(1);
    should(subject.refreshCalls).equal(1);
    should(subject.clearTokenCalls).equal(1);
    should(subject.signInCalls).deepEqual([options]);
  });

  it('serves configured and subsequently replaced token state', async () => {
    // Arrange
    const subject = new FakeAuthProvider({
      idToken: 'initial-id',
      accessTokens: { [RESOURCE]: token('initial-access') },
      signInUrl: 'https://identity.example/authorize',
    });

    // Act
    const initialAccess = await subject.getAccessToken(RESOURCE).serial();
    const initialId = await subject.getIdToken().serial();
    subject.setAccessToken(RESOURCE, token('replaced-access'));
    subject.setIdToken('replaced-id');
    const replacedAccess = await subject.getAccessToken(RESOURCE).serial();
    const replacedId = await subject.getIdToken().serial();
    const signIn = await subject.signInUrl(signInOptions()).serial();

    // Assert
    should(initialAccess).deepEqual(['ok', token('initial-access')]);
    should(initialId).deepEqual(['ok', 'initial-id']);
    should(replacedAccess).deepEqual(['ok', token('replaced-access')]);
    should(replacedId).deepEqual(['ok', 'replaced-id']);
    should(signIn).deepEqual(['ok', 'https://identity.example/authorize']);
  });

  it('runs queued values, Problems, async steps, and thrown failures in order', async () => {
    // Arrange
    const scriptedProblem = problem();
    const mappedProblem = problem('mapped thrown value');
    const subject = new FakeAuthProvider({ mapError: () => mappedProblem });
    subject.enqueueAccessToken(
      RESOURCE,
      token('queued'),
      scriptedProblem,
      async () => token('async'),
      () => {
        throw 'thrown-value';
      },
    );
    subject.enqueueRefresh(scriptedProblem, async () => undefined);
    subject.enqueueIdToken('queued-id', scriptedProblem);
    subject.enqueueClear(scriptedProblem, () => undefined);

    // Act
    const queuedAccess = await subject.getAccessToken(RESOURCE).serial();
    const failedAccess = await subject.getAccessToken(RESOURCE).serial();
    const asyncAccess = await subject.getAccessToken(RESOURCE).serial();
    const thrownAccess = await subject.getAccessToken(RESOURCE).serial();
    const failedRefresh = await subject.refresh().serial();
    const goodRefresh = await subject.refresh().serial();
    const queuedId = await subject.getIdToken().serial();
    const failedId = await subject.getIdToken().serial();
    const failedClear = await subject.clearTokens().serial();
    const goodClear = await subject.clearTokens().serial();

    // Assert
    should(queuedAccess).deepEqual(['ok', token('queued')]);
    should(failedAccess).deepEqual(['err', scriptedProblem]);
    should(asyncAccess).deepEqual(['ok', token('async')]);
    should(thrownAccess).deepEqual(['err', mappedProblem]);
    should(failedRefresh).deepEqual(['err', scriptedProblem]);
    should(goodRefresh[0]).equal('ok');
    should(queuedId).deepEqual(['ok', 'queued-id']);
    should(failedId).deepEqual(['err', scriptedProblem]);
    should(failedClear).deepEqual(['err', scriptedProblem]);
    should(goodClear[0]).equal('ok');
  });
});
