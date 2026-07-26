import type { IAuthStateRetriever } from '@atomicloud/diene.auth-engine';
import authEngine = require('@atomicloud/diene.auth-engine');
import testHelper = require('@atomicloud/diene.auth-engine/test-helper');
import { ProblemRegistry } from '@atomicloud/diene.problems';
import { Ok } from '@atomicloud/diene.result';
import { Temporal } from '@js-temporal/polyfill';

const resources = {
  billing: 'https://api.billing.atomi.dev.cluster.atomi.cloud',
  catalog: 'https://api.catalog.atomi.dev.cluster.atomi.cloud',
} as const;

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(`scratch-consumer CJS assertion failed: ${message}`);
}

async function runRuntimeAssertions(): Promise<void> {
  const assertionNow = Temporal.Instant.from('2026-07-24T12:00:00Z');
  const expiresAt = assertionNow.add({ minutes: 10 });
  const provider = new testHelper.FakeAuthProvider({
    idToken: testHelper.buildUnsignedJwt({ sub: 'scratch-user' }),
    accessTokens: {
      [resources.billing]: { token: 'billing-token', expiresAt },
      [resources.catalog]: { token: 'catalog-token', expiresAt },
    },
  });
  const client = new authEngine.ServerAuthStateRetriever({
    provider,
    resources: {
      'atomi/dev/billing/api': resources.billing,
      'atomi/dev/catalog/api': resources.catalog,
    },
    session: {
      isAuthenticated: () => true,
      getUserInfo: () => Ok({}),
    },
  });
  const tokens = await client.getTokenSet().serial();
  assert(tokens[0] === 'ok' && tokens[1].value.isAuthed, 'both backend tokens should authenticate');
  assert(tokens[1].value.data.accessTokens['atomi/dev/billing/api'] === 'billing-token', 'billing token isolated');
  assert(tokens[1].value.data.accessTokens['atomi/dev/catalog/api'] === 'catalog-token', 'catalog token isolated');

  const registered = await authEngine.registerAuthProblems(
    new ProblemRegistry({
      scheme: 'https',
      host: 'errors.example.invalid',
      landscape: 'dev',
      platform: 'atomi',
      service: 'scratch-consumer',
      module: 'auth',
    }),
  ).serial();
  assert(registered[0] === 'ok', 'auth problems should register');
  const problems = registered[1];
  const store = new testHelper.InMemoryDeferredStore({
    problems,
    clock: { now: () => assertionNow },
  });
  const identity = {
    getUser: () => Ok({ isSuspended: false, primaryEmail: 'scratch@example.invalid' }),
    mintOneTimeToken: (email: string) => Ok({ token: `ott:${email}` }),
  };
  const minted = await authEngine.mintDeferredToken(
    { sub: 'scratch-user', email: 'scratch@example.invalid' },
    {
      store,
      problems,
      clock: { now: () => assertionNow },
    },
  ).serial();
  assert(minted[0] === 'ok', 'deferred mint should succeed');
  assert(
    minted[1].expiresAt.equals(assertionNow.add({ minutes: 15 })),
    'deferred expiry must use the 15-minute Temporal duration',
  );
  const carrier = authEngine.buildIosClipboardPayload(minted[1].nonce);
  const nonce = authEngine.parseCarrier(carrier);
  assert(nonce !== null, 'carrier should round-trip');
  const redeemed = await authEngine.exchangeDeferredToken(
    { nonce, device: { platform: 'ios' } },
    { store, identity, problems },
  ).serial();
  assert(redeemed[0] === 'ok' && redeemed[1].expiresIn === 120, 'redeem must return a 120-second OTT');
  const replay = await authEngine.exchangeDeferredToken(
    { nonce, device: { platform: 'ios' } },
    { store, identity, problems },
  ).serial();
  assert(
    replay[0] === 'err' && replay[1].status === 410 && replay[1].type.endsWith('/app_handoff_expired'),
    'replay must return generic handoff-expired with the lowercase wire id',
  );
}

void runRuntimeAssertions().catch(error => {
  console.error(error);
  process.exitCode = 1;
});

export type ScratchAuthSeam = IAuthStateRetriever;
