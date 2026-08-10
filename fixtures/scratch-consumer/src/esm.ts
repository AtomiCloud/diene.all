import {
  ServerAuthStateRetriever,
  buildIosClipboardPayload,
  exchangeDeferredToken,
  mintDeferredToken,
  parseCarrier,
  registerAuthProblems,
  type AuthProvider,
  type AuthProblems,
  type DeferredIdentityClient,
  type IAuthStateRetriever,
  type TokenSet,
} from '@atomicloud/diene.auth-engine';
import { ProblemRegistry } from '@atomicloud/diene.problems';
import { Ok } from '@atomicloud/diene.result';
import { Temporal } from '@js-temporal/polyfill';
import { buildUnsignedJwt, FakeAuthProvider, InMemoryDeferredStore } from '@atomicloud/diene.auth-engine/test-helper';

const backendResources = {
  'atomi/dev/billing/api': 'https://api.billing.atomi.dev.cluster.atomi.cloud',
  'atomi/dev/catalog/api': 'https://api.catalog.atomi.dev.cluster.atomi.cloud',
} as const;

/**
 * The fixture deliberately exposes the app through the portable IAuth seam.
 * Its real behavior is covered by the package suites; this consumer proves the
 * packed package's public ESM types can wire two backend resources without
 * sharing an implementation-specific cache.
 */
export function createToyBackendClient(provider: AuthProvider = new FakeAuthProvider()): IAuthStateRetriever {
  return new ServerAuthStateRetriever({
    provider,
    resources: backendResources,
    session: {
      isAuthenticated: () => true,
      getUserInfo: () => Ok({}),
    },
  });
}

export async function tokensForBothBackends(client = createToyBackendClient()): Promise<TokenSet | undefined> {
  const result = await client.getTokenSet().serial();
  if (result[0] === 'err') return undefined;
  return result[1].value.isAuthed ? result[1].value.data : undefined;
}

/**
 * A real consumer supplies its registered problems and management-client port.
 * This fixture runs the public mint → carrier → redeem path against the
 * TestHelper store without importing any implementation file.
 */
export async function runDeferredRoundTrip(
  problems: Pick<AuthProblems, 'Unauthorized' | 'AuthRefreshFailed' | 'AppHandoffExpired'>,
  identity: DeferredIdentityClient,
): Promise<string | undefined> {
  const store = new InMemoryDeferredStore({ problems });
  const minted = await mintDeferredToken(
    { sub: 'scratch-user', email: 'scratch@example.invalid' },
    { store, problems },
  ).serial();
  if (minted[0] === 'err') return undefined;

  const nonce = parseCarrier(buildIosClipboardPayload(minted[1].nonce));
  if (nonce === null) return undefined;

  const redeemed = await exchangeDeferredToken(
    { nonce, device: { platform: 'ios' } },
    { store, identity, problems },
  ).serial();
  return redeemed[0] === 'ok' ? redeemed[1].token : undefined;
}

async function scratchProblems(): Promise<AuthProblems> {
  const registered = await registerAuthProblems(
    new ProblemRegistry({
      scheme: 'https',
      host: 'errors.example.invalid',
      landscape: 'dev',
      platform: 'atomi',
      service: 'scratch-consumer',
      module: 'auth',
    }),
  ).serial();
  if (registered[0] === 'err') throw new Error(registered[1].detail);
  return registered[1];
}

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(`scratch-consumer assertion failed: ${message}`);
}

/** Executed by all three runtime probes after the package tarball is installed. */
export async function runRuntimeAssertions(): Promise<void> {
  const assertionNow = Temporal.Instant.from('2026-07-24T12:00:00Z');
  const expiresAt = assertionNow.add({ minutes: 10 });
  const provider = new FakeAuthProvider({
    idToken: buildUnsignedJwt({ sub: 'scratch-user' }),
    accessTokens: {
      [backendResources['atomi/dev/billing/api']]: { token: 'billing-token', expiresAt },
      [backendResources['atomi/dev/catalog/api']]: { token: 'catalog-token', expiresAt },
    },
  });
  const tokens = await tokensForBothBackends(createToyBackendClient(provider));
  assert(tokens !== undefined, 'both backend tokens should authenticate');
  assert(tokens.accessTokens['atomi/dev/billing/api'] === 'billing-token', 'billing token must be isolated');
  assert(tokens.accessTokens['atomi/dev/catalog/api'] === 'catalog-token', 'catalog token must be isolated');
  assert(
    String(tokens.accessTokens['atomi/dev/billing/api']) !== String(tokens.accessTokens['atomi/dev/catalog/api']),
    'backend tokens must not bleed together',
  );

  const problems = await scratchProblems();
  const store = new InMemoryDeferredStore({ problems, clock: { now: () => assertionNow } });
  const identity: DeferredIdentityClient = {
    getUser: () => Ok({ isSuspended: false, primaryEmail: 'scratch@example.invalid' }),
    mintOneTimeToken: email => Ok({ token: `ott:${email}` }),
  };
  const minted = await mintDeferredToken(
    { sub: 'scratch-user', email: 'scratch@example.invalid' },
    {
      store,
      problems,
      clock: { now: () => assertionNow },
    },
  ).serial();
  assert(minted[0] === 'ok', 'deferred mint should succeed');
  const expectedExpiry = assertionNow.add({ minutes: 15 });
  assert(minted[1].expiresAt.equals(expectedExpiry), 'deferred expiry must use the 15-minute Temporal duration');
  const nonce = parseCarrier(buildIosClipboardPayload(minted[1].nonce));
  assert(nonce !== null, 'carrier should round-trip to its nonce');
  const redeemed = await exchangeDeferredToken(
    { nonce, device: { platform: 'ios' } },
    { store, identity, problems },
  ).serial();
  assert(redeemed[0] === 'ok', 'deferred redeem should succeed');
  assert(redeemed[1].expiresIn === 120, 'redeem must use the fixed 120-second OTT lifetime');
  assert(redeemed[1].token === 'ott:scratch@example.invalid', 'redeem should return the identity token');

  const replay = await exchangeDeferredToken(
    { nonce, device: { platform: 'ios' } },
    { store, identity, problems },
  ).serial();
  assert(replay[0] === 'err', 'replaying a consumed nonce must fail');
  assert(replay[1].status === 410, 'replay must return the generic handoff-expired problem');
  assert(
    replay[1].type.endsWith('/app_handoff_expired'),
    'replay must preserve the lowercase app_handoff_expired wire id',
  );
}

await runRuntimeAssertions();
