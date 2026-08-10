import { describe, it } from 'bun:test';
import { Temporal } from '@js-temporal/polyfill';
import should from 'should';
import { decodeToken } from '../../src/lib/jwt';
import {
  buildClaims,
  buildDeferredNonceRecord,
  buildProblemFixture,
  buildTokenSet,
  buildUnsignedJwt,
} from '../../src/test-helper';
import { testAuthProblems } from '../support/auth-problems';

describe('TestHelper builders', () => {
  it('builds decodable unsigned JWTs with claims and custom headers', async () => {
    // Arrange
    const claims = buildClaims({ sub: 'builder-user', role: 'admin' });

    // Act
    const token = buildUnsignedJwt(claims, { kid: 'fixture-key' });
    const actual = await decodeToken(token).serial();

    // Assert
    should(actual[0]).equal('ok');
    if (actual[0] !== 'ok') return;
    should(actual[1]).containEql({
      sub: 'builder-user',
      email: 'test@example.invalid',
      role: 'admin',
    });
  });

  it('builds a default claims fixture and token set with per-resource claims', async () => {
    // Arrange
    const resource = 'alcohol/lapras/zinc/api' as const;

    // Act
    const defaults = buildClaims();
    const tokenSet = buildTokenSet({
      idTokenClaims: { sub: 'id-user' },
      accessTokenClaims: { [resource]: { aud: 'zinc-api' } },
    });
    const idClaims = await decodeToken(tokenSet.idToken).serial();
    const accessClaims = await decodeToken(tokenSet.accessTokens[resource] ?? 'missing-token').serial();
    const defaultTokenSet = buildTokenSet();

    // Assert
    should(defaults).containEql({ sub: 'test-user', email: 'test@example.invalid' });
    should(idClaims[0]).equal('ok');
    should(accessClaims[0]).equal('ok');
    if (idClaims[0] === 'ok') should(idClaims[1].sub).equal('id-user');
    if (accessClaims[0] === 'ok') should(accessClaims[1].aud).equal('zinc-api');
    should(defaultTokenSet.accessTokens).deepEqual({});
  });

  it('builds deferred records with Temporal.Instant expiry and immutable overrides', () => {
    // Arrange
    const expiry = Temporal.Instant.from('2031-02-03T04:05:06Z');

    // Act
    const defaults = buildDeferredNonceRecord();
    const actual = buildDeferredNonceRecord({ sub: 'override-user', expiresAt: expiry, state: 'claimed' });

    // Assert
    should(defaults.expiresAt instanceof Temporal.Instant).be.true();
    should(actual.sub).equal('override-user');
    should(actual.expiresAt.equals(expiry)).be.true();
    should(actual.state).equal('claimed');
  });

  it('builds Problems through the registered definition schema', () => {
    // Arrange
    const problems = testAuthProblems();

    // Act
    const actual = buildProblemFixture(problems.InvalidReturnTo, {
      detail: 'fixture detail',
      data: {},
    });

    // Assert
    should(actual.type).equal(problems.InvalidReturnTo.type);
    should(actual.status).equal(400);
    should(actual.detail).equal('fixture detail');
    should(actual.data).deepEqual({});
  });
});
