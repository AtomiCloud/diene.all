import { describe, it } from 'bun:test';
import type { Problem } from '@atomicloud/diene.problems';
import should from 'should';
import type { TokenSet } from '../../src/lib/retriever';
import {
  buildTokenSet,
  FakeAuthStateRetriever,
  FakeClientAuthStateRetriever,
  FakeServerAuthStateRetriever,
} from '../../src/test-helper';

function retrieverProblem(): Problem {
  return {
    type: 'about:blank',
    title: 'Retriever failure',
    status: 503,
    detail: 'The fake retriever was instructed to fail.',
    data: {},
  };
}

function replacementTokenSet(): TokenSet {
  return buildTokenSet({ idTokenClaims: { sub: 'replacement-user' } });
}

describe('FakeAuthStateRetriever', () => {
  it('returns every configured authenticated state and records seam calls', async () => {
    // Arrange
    const tokens = buildTokenSet({ idTokenClaims: { sub: 'configured-user' } });
    const claims = { sub: 'configured-user', role: 'admin' };
    const user = { displayName: 'Configured User' };
    const subject = new FakeAuthStateRetriever({ tokenSet: tokens, claims, userInfo: user });

    // Act
    const tokenResult = await subject.getTokenSet().serial();
    const claimResult = await subject.getClaims().serial();
    const userResult = await subject.getUserInfo().serial();
    const statesResult = await subject.getStates().serial();

    // Assert
    should(tokenResult[0]).equal('ok');
    should(claimResult[0]).equal('ok');
    should(userResult[0]).equal('ok');
    should(statesResult[0]).equal('ok');
    if (tokenResult[0] !== 'ok' || claimResult[0] !== 'ok' || userResult[0] !== 'ok' || statesResult[0] !== 'ok') {
      return;
    }
    should(tokenResult[1].value).deepEqual({ isAuthed: true, data: tokens });
    should(claimResult[1].value).deepEqual({ isAuthed: true, data: claims });
    should(userResult[1].value).deepEqual({ isAuthed: true, data: user });
    should(statesResult[1].value).deepEqual({
      isAuthed: true,
      data: { tokens, claims, user },
    });
    should(subject.getTokenSetCalls).equal(1);
    should(subject.getClaimsCalls).equal(1);
    should(subject.getUserInfoCalls).equal(1);
    should(subject.getStatesCalls).equal(1);
  });

  it('returns unauthenticated states after the explicit state seam changes', async () => {
    // Arrange
    const subject = new FakeAuthStateRetriever();
    subject.setAuthenticated(false);

    // Act
    const tokens = await subject.getTokenSet().serial();
    const claims = await subject.getClaims().serial();
    const user = await subject.getUserInfo().serial();
    const states = await subject.getStates().serial();

    // Assert
    should(tokens).deepEqual(['ok', { __kind: 'unauthed', value: { isAuthed: false } }]);
    should(claims).deepEqual(['ok', { __kind: 'unauthed', value: { isAuthed: false } }]);
    should(user).deepEqual(['ok', { __kind: 'unauthed', value: { isAuthed: false } }]);
    should(states).deepEqual(['ok', { __kind: 'unauthed', value: { isAuthed: false } }]);
  });

  it('runs forced token steps in order and keeps the last replacement', async () => {
    // Arrange
    const subject = new FakeAuthStateRetriever();
    const problem = retrieverProblem();
    const directlySet = buildTokenSet({ idTokenClaims: { sub: 'direct-user' } });
    const forced = replacementTokenSet();
    subject.setTokenSet(directlySet);
    subject.enqueueForced('unauthed', problem, forced);

    // Act
    const unauthenticated = await subject.forceTokenSet().serial();
    const failed = await subject.forceTokenSet().serial();
    const replaced = await subject.forceTokenSet().serial();
    const retained = await subject.forceTokenSet().serial();

    // Assert
    should(unauthenticated).deepEqual(['ok', { __kind: 'unauthed', value: { isAuthed: false } }]);
    should(failed).deepEqual(['err', problem]);
    should(replaced[0]).equal('ok');
    should(retained[0]).equal('ok');
    if (replaced[0] === 'ok') should(replaced[1].value).deepEqual({ isAuthed: true, data: forced });
    if (retained[0] === 'ok') should(retained[1].value).deepEqual({ isAuthed: true, data: forced });
    should(subject.forceTokenSetCalls).equal(4);
  });

  it('returns and clears a configured failure across every Result seam', async () => {
    // Arrange
    const problem = retrieverProblem();
    const subject = new FakeAuthStateRetriever({ problem });

    // Act
    const tokens = await subject.getTokenSet().serial();
    const claims = await subject.getClaims().serial();
    const user = await subject.getUserInfo().serial();
    const states = await subject.getStates().serial();
    const forced = await subject.forceTokenSet().serial();
    subject.setProblem();
    const recovered = await subject.getTokenSet().serial();

    // Assert
    should(tokens).deepEqual(['err', problem]);
    should(claims).deepEqual(['err', problem]);
    should(user).deepEqual(['err', problem]);
    should(states).deepEqual(['err', problem]);
    should(forced).deepEqual(['err', problem]);
    should(recovered[0]).equal('ok');
  });

  it('provides client and server seam-specific fake types', async () => {
    // Arrange
    const client = new FakeClientAuthStateRetriever({ authenticated: false });
    const server = new FakeServerAuthStateRetriever({ authenticated: false });

    // Act
    const clientResult = await client.getStates().serial();
    const serverResult = await server.getStates().serial();

    // Assert
    should(clientResult).deepEqual(['ok', { __kind: 'unauthed', value: { isAuthed: false } }]);
    should(serverResult).deepEqual(['ok', { __kind: 'unauthed', value: { isAuthed: false } }]);
  });
});
