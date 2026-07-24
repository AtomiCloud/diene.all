import { describe, it } from 'bun:test';
import { Err, Ok } from '@atomicloud/diene.result';
import should from 'should';
import {
  type ExchangeDeferredTokenDeps,
  exchangeDeferredToken,
  ONE_TIME_TOKEN_EXPIRES_IN_SECONDS,
} from '../../../src/lib/deferred/exchange';
import { claimedRecord, genericExpiry, ScriptedIdentityClient, ScriptedStore, testAuthProblems } from './support';

const problems = testAuthProblems();

function depsFor(store: ScriptedStore, identity: ScriptedIdentityClient): ExchangeDeferredTokenDeps {
  return { store, identity, problems };
}

const validInput = { nonce: 'a'.repeat(43), device: { platform: 'android', appVersion: '1.2.3' } };

describe('exchangeDeferredToken', () => {
  it('mints a one-time token on the happy path and returns the current email', async () => {
    // Arrange
    const store = new ScriptedStore({ claim: Ok(claimedRecord({ email: 'user@example.com' })) });
    const identity = new ScriptedIdentityClient({
      getUser: Ok({ isSuspended: false, primaryEmail: 'User@Example.com' }),
      mint: Ok({ token: 'ott_success' }),
    });

    // Act
    const actual = await exchangeDeferredToken(validInput, depsFor(store, identity)).unwrap();

    // Assert
    should(actual).eql({
      token: 'ott_success',
      email: 'User@Example.com',
      expiresIn: ONE_TIME_TOKEN_EXPIRES_IN_SECONDS,
    });
    should(identity.calls.getUser).equal(1);
    should(identity.calls.mint).equal(1);
    should(identity.lastMintEmail).equal('User@Example.com');
    should(store.calls.consume).equal(1);
    should(store.calls.revoke).equal(0);
  });

  it('rejects unknown top-level keys before any store hit', async () => {
    // Arrange
    const store = new ScriptedStore();
    const input = { nonce: 'a'.repeat(43), extra: 'nope' };

    // Act
    const result = exchangeDeferredToken(input, depsFor(store, new ScriptedIdentityClient()));

    // Assert
    should(await result.isErr()).be.true();
    should((await result.unwrapErr()).status).equal(410);
    should(store.calls.claim).equal(0);
  });

  it('rejects unknown device keys before any store hit', async () => {
    // Arrange
    const store = new ScriptedStore();
    const input = { nonce: 'a'.repeat(43), device: { platform: 'ios', trackingId: 'x' } };

    // Act
    const actual = await exchangeDeferredToken(input, depsFor(store, new ScriptedIdentityClient())).isErr();

    // Assert
    should(actual).be.true();
    should(store.calls.claim).equal(0);
  });

  it('rejects a blank nonce before any store hit (M33)', async () => {
    // Arrange
    const store = new ScriptedStore();
    const input = { nonce: '   ' };

    // Act
    const actual = await exchangeDeferredToken(input, depsFor(store, new ScriptedIdentityClient())).isErr();

    // Assert
    should(actual).be.true();
    should(store.calls.claim).equal(0);
  });

  it('rejects every malformed nonce shape before any store hit', async () => {
    // Arrange
    const malformed = ['a'.repeat(42), 'a'.repeat(44), `${'a'.repeat(42)}!`, 123];

    // Act
    const outcomes = await Promise.all(
      malformed.map(async nonce => {
        const store = new ScriptedStore();
        const result = await exchangeDeferredToken({ nonce }, depsFor(store, new ScriptedIdentityClient())).serial();
        return { result, claims: store.calls.claim };
      }),
    );

    // Assert
    should(outcomes.every(outcome => outcome.result[0] === 'err')).be.true();
    should(outcomes.map(outcome => outcome.claims)).deepEqual([0, 0, 0, 0]);
  });

  it('returns generic expiry when the claim fails, without touching Logto', async () => {
    // Arrange
    const store = new ScriptedStore({ claim: Err(genericExpiry()) });
    const identity = new ScriptedIdentityClient();

    // Act
    const actual = await exchangeDeferredToken(validInput, depsFor(store, identity)).isErr();

    // Assert
    should(actual).be.true();
    should(store.calls.claim).equal(1);
    should(identity.calls.getUser).equal(0);
    should(store.calls.revoke).equal(0);
  });

  it('revokes and returns generic expiry when the user lookup fails (deleted/404)', async () => {
    // Arrange
    const store = new ScriptedStore({ claim: Ok(claimedRecord()) });
    const identity = new ScriptedIdentityClient({ getUser: Err(genericExpiry()) });

    // Act
    const actual = await exchangeDeferredToken(validInput, depsFor(store, identity)).isErr();

    // Assert
    should(actual).be.true();
    should(store.calls.revoke).equal(1);
    should(identity.calls.mint).equal(0);
  });

  it('revokes and returns generic expiry when the account is suspended', async () => {
    // Arrange
    const store = new ScriptedStore({ claim: Ok(claimedRecord({ email: 'user@example.com' })) });
    const identity = new ScriptedIdentityClient({
      getUser: Ok({ isSuspended: true, primaryEmail: 'user@example.com' }),
    });

    // Act
    const actual = await exchangeDeferredToken(validInput, depsFor(store, identity)).isErr();

    // Assert
    should(actual).be.true();
    should(store.calls.revoke).equal(1);
    should(identity.calls.mint).equal(0);
  });

  it('revokes and returns generic expiry when the primary email is null', async () => {
    // Arrange
    const store = new ScriptedStore({ claim: Ok(claimedRecord({ email: 'user@example.com' })) });
    const identity = new ScriptedIdentityClient({
      getUser: Ok({ isSuspended: false, primaryEmail: null }),
    });

    // Act
    const actual = await exchangeDeferredToken(validInput, depsFor(store, identity)).isErr();

    // Assert
    should(actual).be.true();
    should(store.calls.revoke).equal(1);
    should(identity.calls.mint).equal(0);
  });

  it('revokes and returns generic expiry when the email was rebound (mismatch)', async () => {
    // Arrange
    const store = new ScriptedStore({ claim: Ok(claimedRecord({ email: 'user@example.com' })) });
    const identity = new ScriptedIdentityClient({
      getUser: Ok({ isSuspended: false, primaryEmail: 'attacker@example.com' }),
    });

    // Act
    const actual = await exchangeDeferredToken(validInput, depsFor(store, identity)).isErr();

    // Assert
    should(actual).be.true();
    should(store.calls.revoke).equal(1);
    should(identity.calls.mint).equal(0);
  });

  it('revokes and returns generic expiry when the token mint fails', async () => {
    // Arrange
    const store = new ScriptedStore({ claim: Ok(claimedRecord({ email: 'user@example.com' })) });
    const identity = new ScriptedIdentityClient({
      getUser: Ok({ isSuspended: false, primaryEmail: 'user@example.com' }),
      mint: Err(genericExpiry()),
    });

    // Act
    const actual = await exchangeDeferredToken(validInput, depsFor(store, identity)).isErr();

    // Assert
    should(actual).be.true();
    should(store.calls.revoke).equal(1);
    should(store.calls.consume).equal(0);
  });

  it('fails closed (no token returned) when consume fails after mint', async () => {
    // Arrange
    const store = new ScriptedStore({
      claim: Ok(claimedRecord({ email: 'user@example.com' })),
      consume: Err(genericExpiry()),
    });
    const identity = new ScriptedIdentityClient({
      getUser: Ok({ isSuspended: false, primaryEmail: 'user@example.com' }),
      mint: Ok({ token: 'ott_orphaned' }),
    });

    // Act
    const actual = await exchangeDeferredToken(validInput, depsFor(store, identity)).isErr();

    // Assert
    should(actual).be.true();
    should(store.calls.consume).equal(1);
    should(store.calls.revoke).equal(0);
  });

  it('accepts valid device telemetry without letting it affect the outcome', async () => {
    // Arrange
    const store = new ScriptedStore({ claim: Ok(claimedRecord({ email: 'user@example.com' })) });
    const identity = new ScriptedIdentityClient({
      getUser: Ok({ isSuspended: false, primaryEmail: 'user@example.com' }),
      mint: Ok({ token: 'ott_device' }),
    });
    const input = { nonce: 'a'.repeat(43), device: { platform: 'ios', osVersion: '18.0', model: 'iPhone' } };

    // Act
    const actual = await exchangeDeferredToken(input, depsFor(store, identity)).isOk();

    // Assert
    should(actual).be.true();
  });
});
