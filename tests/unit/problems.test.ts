import { describe, it } from 'bun:test';
import { ProblemRegistry } from '@atomicloud/diene.problems';
import should from 'should';
import {
  APP_HANDOFF_EXPIRED_DETAIL,
  AppHandoffExpired,
  AuthRefreshFailed,
  createAppHandoffExpired,
  createAuthRefreshFailed,
  createInvalidReturnTo,
  createOnboardingClaimMissing,
  createUnauthorized,
  InvalidReturnTo,
  OnboardingClaimMissing,
  registerAuthProblems,
} from '../../src/lib/problems';
import { testAuthProblems } from '../support/auth-problems';

function problemRegistry(): ProblemRegistry {
  return new ProblemRegistry({
    scheme: 'https',
    host: 'errors.atomi.cloud',
    landscape: 'lapras',
    platform: 'alcohol',
    service: 'argon',
    module: 'auth',
  });
}

describe('auth problems', () => {
  it('preserves exact amended C0 wire-id contract parity behind PascalCase API names', async () => {
    // Arrange
    const registry = problemRegistry();

    // Act
    const first = await registerAuthProblems(registry).serial();
    const second = await registerAuthProblems(registry).serial();

    // Assert
    should(first[0]).equal('ok');
    should(second[0]).equal('ok');
    if (first[0] !== 'ok' || second[0] !== 'ok') return;
    should(second[1]).deepEqual(first[1]);
    should(registry.list().map(problem => problem.id)).deepEqual([
      'app_handoff_expired',
      'auth_refresh_failed',
      'invalid_return_to',
      'onboarding_claim_missing',
      'unauthorized',
    ]);
    should([
      ['AppHandoffExpired', first[1].AppHandoffExpired.id, first[1].AppHandoffExpired.type],
      ['OnboardingClaimMissing', first[1].OnboardingClaimMissing.id, first[1].OnboardingClaimMissing.type],
      ['AuthRefreshFailed', first[1].AuthRefreshFailed.id, first[1].AuthRefreshFailed.type],
      ['InvalidReturnTo', first[1].InvalidReturnTo.id, first[1].InvalidReturnTo.type],
    ]).deepEqual([
      [
        'AppHandoffExpired',
        'app_handoff_expired',
        'https://errors.atomi.cloud/docs/lapras/alcohol/argon/auth/v1/app_handoff_expired',
      ],
      [
        'OnboardingClaimMissing',
        'onboarding_claim_missing',
        'https://errors.atomi.cloud/docs/lapras/alcohol/argon/auth/v1/onboarding_claim_missing',
      ],
      [
        'AuthRefreshFailed',
        'auth_refresh_failed',
        'https://errors.atomi.cloud/docs/lapras/alcohol/argon/auth/v1/auth_refresh_failed',
      ],
      [
        'InvalidReturnTo',
        'invalid_return_to',
        'https://errors.atomi.cloud/docs/lapras/alcohol/argon/auth/v1/invalid_return_to',
      ],
    ]);
    should(
      [AppHandoffExpired, AuthRefreshFailed, InvalidReturnTo, OnboardingClaimMissing].map(
        definition => definition.version,
      ),
    ).deepEqual(['v1', 'v1', 'v1', 'v1']);
  });

  it('returns a typed Problem instead of throwing when registration cannot bind a URI', async () => {
    // Arrange
    const registry = new ProblemRegistry({
      scheme: 'https',
      host: 'not a host',
      landscape: 'lapras',
      platform: 'alcohol',
      service: 'argon',
      module: 'auth',
    });

    // Act
    const actual = await registerAuthProblems(registry).serial();

    // Assert
    should(actual[0]).equal('err');
    if (actual[0] !== 'err') return;
    should(actual[1].type).equal('about:blank');
    should(actual[1].status).equal(502);
    should(actual[1].title).equal('Authentication refresh failed');
  });

  it('rejects an incompatible reused definition without partially registering the catalog', async () => {
    // Arrange
    const registry = problemRegistry();
    registry.register({ ...InvalidReturnTo, title: 'Conflicting return target' });

    // Act
    const actual = await registerAuthProblems(registry).serial();

    // Assert
    should(actual[0]).equal('err');
    should(registry.list().map(problem => problem.id)).deepEqual(['invalid_return_to']);
  });

  it('creates the fixed no-oracle handoff problem', () => {
    // Arrange
    const problems = testAuthProblems();

    // Act
    const actual = createAppHandoffExpired(problems);

    // Assert
    should(actual.status).equal(410);
    should(actual.title).equal('App handoff expired');
    should(actual.detail).equal(APP_HANDOFF_EXPIRED_DETAIL);
    should(actual.data).deepEqual({});
  });

  it('creates onboarding, refresh, returnTo, and unauthorized instances', () => {
    // Arrange
    const problems = testAuthProblems();

    // Act
    const onboarding = createOnboardingClaimMissing(problems);
    const backendOnboarding = createOnboardingClaimMissing(problems, 'zinc');
    const refresh = createAuthRefreshFailed(problems);
    const customRefresh = createAuthRefreshFailed(problems, 'custom refresh detail');
    const invalidReturnTo = createInvalidReturnTo(problems);
    const customInvalidReturnTo = createInvalidReturnTo(problems, 'bad target');
    const unauthorized = createUnauthorized(problems);
    const customUnauthorized = createUnauthorized(problems, 'session ended');

    // Assert
    should(onboarding.detail).containEql('still missing');
    should(onboarding.status).equal(409);
    should(backendOnboarding.detail).containEql('zinc');
    should(refresh.detail).containEql('could not be refreshed');
    should(customRefresh.detail).equal('custom refresh detail');
    should(invalidReturnTo.status).equal(400);
    should(customInvalidReturnTo.detail).equal('bad target');
    should(unauthorized.data).deepEqual({ reason: 'Authentication is required.' });
    should(customUnauthorized.detail).equal('session ended');
  });
});
