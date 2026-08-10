import { ProblemRegistry, Unauthorized } from '@atomicloud/diene.problems';
import {
  AppHandoffExpired,
  AUTH_PROBLEM_VERSION,
  type AuthProblems,
  AuthRefreshFailed,
  InvalidReturnTo,
  OnboardingClaimMissing,
} from '../../src/lib/problems';

/**
 * A fully-registered {@link AuthProblems} bag for tests across all tiers.
 *
 * C0 wire-id parity keeps exported API symbols/map keys in PascalCase while the
 * definitions themselves carry package-valid snake_case wire ids. Register the
 * exported definitions unchanged so this fixture proves the amended contract.
 */
export function testAuthProblems(): AuthProblems {
  const registry = new ProblemRegistry({
    scheme: 'https',
    host: 'errors.example.com',
    landscape: 'lapras',
    platform: 'atomi',
    service: 'auth-engine',
    module: 'engine',
  });
  return Object.freeze({
    AppHandoffExpired: registry.register(AppHandoffExpired),
    OnboardingClaimMissing: registry.register(OnboardingClaimMissing),
    AuthRefreshFailed: registry.register(AuthRefreshFailed),
    InvalidReturnTo: registry.register(InvalidReturnTo),
    Unauthorized: registry.register({ ...Unauthorized, version: AUTH_PROBLEM_VERSION }),
  });
}
