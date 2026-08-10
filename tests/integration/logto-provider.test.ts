import { afterAll, beforeAll, beforeEach, describe, it } from 'bun:test';
import type { Problem } from '@atomicloud/diene.problems';
import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { Temporal } from '@js-temporal/polyfill';
import should from 'should';
import {
  createLogtoAuthProvider,
  type LogtoAuthProvider,
  type LogtoFetchLike,
  type LogtoTokenSession,
  type LogtoTokenStorage,
} from '../../src/adapters/logto/provider';
import type { AuthClock } from '../../src/lib/provider';
import { testAuthProblems } from '../support/auth-problems';

const problems = testAuthProblems();

const APP_ID = 'app_1';
const APP_SECRET = 'app_secret';

/** A JSON token endpoint response the mock IdP returns for the next grant. */
type TokenReply = { status: number; body: Record<string, unknown> };

let server: ReturnType<typeof Bun.serve> | undefined;
let baseUrl = '';

// Mutable per-test wiring for the mock IdP.
let authCodeReply: TokenReply;
let refreshReply: TokenReply;
let lastClientSecret: string | null;
let lastGrantType: string | null;
let lastRefreshTokenSent: string | null;
let tokenCalls: number;
const revokedTokens: string[] = [];

beforeAll(() => {
  server = Bun.serve({
    port: 0,
    async fetch(request) {
      const url = new URL(request.url);
      const params = new URLSearchParams(await request.text());

      if (url.pathname === '/oidc/token') {
        tokenCalls += 1;
        lastClientSecret = params.get('client_secret');
        lastGrantType = params.get('grant_type');
        if (lastGrantType === 'refresh_token') {
          lastRefreshTokenSent = params.get('refresh_token');
          return Response.json(refreshReply.body, { status: refreshReply.status });
        }
        return Response.json(authCodeReply.body, { status: authCodeReply.status });
      }

      if (url.pathname === '/oidc/token/revocation') {
        revokedTokens.push(params.get('token') ?? '');
        return new Response(null, { status: 200 });
      }

      return new Response('not found', { status: 404 });
    },
  });
  baseUrl = `http://localhost:${server.port}`;
});

afterAll(() => {
  server?.stop(true);
});

beforeEach(() => {
  authCodeReply = {
    status: 200,
    body: { access_token: 'at_code', refresh_token: 'rt_code', id_token: 'id_code', scope: 'openid', expires_in: 600 },
  };
  refreshReply = {
    status: 200,
    body: { access_token: 'at_next', refresh_token: 'rt_next', id_token: 'id_next', scope: 'openid', expires_in: 600 },
  };
  lastClientSecret = null;
  lastGrantType = null;
  lastRefreshTokenSent = null;
  tokenCalls = 0;
  revokedTokens.length = 0;
});

const FIXED_NOW = Temporal.Instant.from('2026-07-24T00:00:00Z');

function fixedClock(instant: Temporal.Instant = FIXED_NOW): AuthClock {
  return { now: () => instant };
}

/**
 * Local scriptable session storage double for these tests. The production adapter
 * ships no in-memory storage; consumers inject their own port implementation.
 */
class InMemoryStorage implements LogtoTokenStorage {
  #session: LogtoTokenSession | undefined;

  constructor(session?: LogtoTokenSession) {
    this.#session = session;
  }

  get(): Result<LogtoTokenSession | undefined, Problem> {
    return Ok(this.#session);
  }

  set(session: LogtoTokenSession): Result<void, Problem> {
    this.#session = session;
    return Ok(undefined);
  }

  clear(): Result<void, Problem> {
    this.#session = undefined;
    return Ok(undefined);
  }
}

class FailingSetStorage implements LogtoTokenStorage {
  session: LogtoTokenSession | undefined;
  clearCalls = 0;
  readonly failure: Problem;

  constructor(session: LogtoTokenSession | undefined, failure: Problem) {
    this.session = session;
    this.failure = failure;
  }

  get(): Result<LogtoTokenSession | undefined, Problem> {
    return Ok(this.session);
  }

  set(): Result<void, Problem> {
    return Err(this.failure);
  }

  clear(): Result<void, Problem> {
    this.clearCalls += 1;
    this.session = undefined;
    return Ok(undefined);
  }
}

function storageFailure(): Problem {
  return {
    type: 'about:blank',
    title: 'Storage failure',
    status: 500,
    detail: 'The session could not be persisted.',
    data: {},
  };
}

async function makeProviderAsync(options: {
  session?: LogtoTokenSession;
  clock?: AuthClock;
  tokenSkew?: Temporal.Duration;
}): Promise<{ provider: LogtoAuthProvider; storage: InMemoryStorage }> {
  const storage = new InMemoryStorage(options.session);
  const provider = await createLogtoAuthProvider({
    endpoint: baseUrl,
    appId: APP_ID,
    appSecret: APP_SECRET,
    storage,
    problems,
    clock: options.clock ?? fixedClock(),
    tokenSkew: options.tokenSkew,
  }).unwrap();
  return { provider, storage };
}

describe('createLogtoAuthProvider', () => {
  it('rejects an invalid configuration via Zod safeParse', async () => {
    // Arrange
    const storage = new InMemoryStorage();

    // Act
    const built = createLogtoAuthProvider({
      endpoint: '',
      appId: APP_ID,
      appSecret: APP_SECRET,
      storage,
      problems,
      clock: fixedClock(),
    });

    // Assert
    should(await built.isErr()).be.true();
    should((await built.unwrapErr()).status).equal(502);
  });

  it('rejects blank final credentials through Zod safeParse', async () => {
    // Arrange
    const storage = new InMemoryStorage();

    // Act
    const built = createLogtoAuthProvider({
      endpoint: baseUrl,
      appId: APP_ID,
      appSecret: '  ',
      storage,
      problems,
      clock: fixedClock(),
    });

    // Assert
    should(await built.isErr()).be.true();
    should((await built.unwrapErr()).status).equal(502);
  });

  it('rejects a Logto endpoint that is not a canonical origin', async () => {
    // Arrange
    const storage = new InMemoryStorage();

    // Act
    const built = createLogtoAuthProvider({
      endpoint: `${baseUrl}/tenant?source=config`,
      appId: APP_ID,
      appSecret: APP_SECRET,
      storage,
      problems,
      clock: fixedClock(),
    });

    // Assert
    should(await built.isErr()).be.true();
    should(tokenCalls).equal(0);
  });

  it('preserves significant whitespace in an opaque injected client secret', async () => {
    // Arrange
    const storage = new InMemoryStorage();
    let observedSecret: string | null = null;
    const fetchLike: LogtoFetchLike = async (_input, init) => {
      observedSecret = new URLSearchParams(String(init?.body)).get('client_secret');
      return Response.json(authCodeReply.body, { status: authCodeReply.status });
    };
    const provider = await createLogtoAuthProvider({
      endpoint: baseUrl,
      appId: APP_ID,
      appSecret: ' app secret ',
      storage,
      problems,
      clock: fixedClock(),
      fetch: fetchLike,
    }).unwrap();

    // Act
    const exchanged = await provider
      .exchangeAuthorizationCode({
        code: 'auth_code',
        redirectUri: 'https://app.example.com/callback',
        codeVerifier: 'verifier',
      })
      .isOk();

    // Assert
    should(exchanged).be.true();
    should(observedSecret).equal(' app secret ');
  });

  it('rejects negative or calendar-unit token skew through Zod safeParse', async () => {
    // Arrange
    const storage = new InMemoryStorage();

    // Act
    const negative = createLogtoAuthProvider({
      endpoint: baseUrl,
      appId: APP_ID,
      appSecret: APP_SECRET,
      storage,
      problems,
      clock: fixedClock(),
      tokenSkew: Temporal.Duration.from({ seconds: -1 }),
    });
    const calendarUnit = createLogtoAuthProvider({
      endpoint: baseUrl,
      appId: APP_ID,
      appSecret: APP_SECRET,
      storage,
      problems,
      clock: fixedClock(),
      tokenSkew: Temporal.Duration.from({ months: 1 }),
    });

    // Assert
    should(await negative.isErr()).be.true();
    should(await calendarUnit.isErr()).be.true();
  });
});

describe('LogtoAuthProvider — authorization-code flow', () => {
  it('exchanges an authorization code through the SDK and stores the session', async () => {
    // Arrange
    const { provider, storage } = await makeProviderAsync({});

    // Act
    const exchanged = provider.exchangeAuthorizationCode({
      code: 'auth_code',
      redirectUri: 'https://app.example.com/callback',
      codeVerifier: 'verifier',
      resource: 'https://api.example.com',
    });

    // Assert
    should(await exchanged.isOk()).be.true();
    should(lastGrantType).equal('authorization_code');
    should(lastClientSecret).equal(APP_SECRET);
    const session = await storage.get().unwrap();
    should(session?.refreshToken).equal('rt_code');
    should(session?.idToken).equal('id_code');
    should(session?.accessTokens['https://api.example.com']?.token).equal('at_code');
  });

  it('fails typed when the authorization-code response omits a refresh token', async () => {
    // Arrange
    authCodeReply = {
      status: 200,
      body: { access_token: 'at_code', id_token: 'id_code', scope: 'openid', expires_in: 600 },
    };
    const { provider, storage } = await makeProviderAsync({});

    // Act
    const exchanged = provider.exchangeAuthorizationCode({
      code: 'auth_code',
      redirectUri: 'https://app.example.com/callback',
      codeVerifier: 'verifier',
    });

    // Assert
    should(await exchanged.isErr()).be.true();
    should((await exchanged.unwrapErr()).status).equal(502);
    should(await storage.get().unwrap()).be.undefined();
  });

  it('revokes and clears a returned refresh token when the access token is malformed', async () => {
    // Arrange
    authCodeReply = {
      status: 200,
      body: { access_token: '   ', refresh_token: 'rt_code', id_token: 'id_code', scope: 'openid', expires_in: 600 },
    };
    const { provider, storage } = await makeProviderAsync({});

    // Act
    const exchanged = provider.exchangeAuthorizationCode({
      code: 'auth_code',
      redirectUri: 'https://app.example.com/callback',
      codeVerifier: 'verifier',
    });

    // Assert
    should(await exchanged.isErr()).be.true();
    should(revokedTokens).containEql('rt_code');
    should(await storage.get().unwrap()).be.undefined();
  });

  it('revokes and clears a returned refresh token when session persistence fails', async () => {
    // Arrange
    const failure = storageFailure();
    const storage = new FailingSetStorage(undefined, failure);
    const provider = await createLogtoAuthProvider({
      endpoint: baseUrl,
      appId: APP_ID,
      appSecret: APP_SECRET,
      storage,
      problems,
      clock: fixedClock(),
    }).unwrap();

    // Act
    const exchanged = await provider
      .exchangeAuthorizationCode({
        code: 'auth_code',
        redirectUri: 'https://app.example.com/callback',
        codeVerifier: 'verifier',
      })
      .serial();

    // Assert
    should(exchanged).deepEqual(['err', failure]);
    should(revokedTokens).containEql('rt_code');
    should(storage.clearCalls).equal(1);
    should(storage.session).be.undefined();
  });

  it('revokes and clears when the SDK response fails schema validation (bad expiry)', async () => {
    // Arrange
    authCodeReply = { status: 200, body: { access_token: 'at_code', scope: 'openid', expires_in: 'soon' } };
    const { provider, storage } = await makeProviderAsync({});

    // Act
    const exchanged = provider.exchangeAuthorizationCode({
      code: 'auth_code',
      redirectUri: 'https://app.example.com/callback',
      codeVerifier: 'verifier',
    });

    // Assert
    should(await exchanged.isErr()).be.true();
    should(tokenCalls).equal(1);
    should(revokedTokens).have.length(0);
    should(await storage.get().unwrap()).be.undefined();
  });

  it('rejects invalid public exchange coordinates before calling the SDK', async () => {
    // Arrange
    const { provider } = await makeProviderAsync({});

    // Act
    const actual = await provider
      .exchangeAuthorizationCode({ code: ' ', redirectUri: 'not-a-url', codeVerifier: '' })
      .serial();

    // Assert
    should(actual[0]).equal('err');
    should(tokenCalls).equal(0);
  });

  it('rejects credentialed, fragmented, or fragment-bearing OAuth exchange URLs', async () => {
    // Arrange
    const { provider } = await makeProviderAsync({});
    const inputs = [
      {
        code: 'code',
        redirectUri: 'https://user:pass@app.example.com/callback',
        codeVerifier: 'verifier',
      },
      {
        code: 'code',
        redirectUri: 'https://app.example.com/callback#fragment',
        codeVerifier: 'verifier',
      },
      {
        code: 'code',
        redirectUri: 'https://app.example.com/callback',
        codeVerifier: 'verifier',
        resource: 'https://api.example.com#fragment',
      },
    ];

    // Act
    const results = await Promise.all(inputs.map(input => provider.exchangeAuthorizationCode(input).serial()));

    // Assert
    should(results.map(result => result[0])).deepEqual(['err', 'err', 'err']);
    should(tokenCalls).equal(0);
  });
});

describe('LogtoAuthProvider — access tokens and caching', () => {
  it('serves a still-fresh cached access token without calling the IdP', async () => {
    // Arrange
    const cached = { token: 'at_cached', expiresAt: FIXED_NOW.add({ minutes: 9 }) };
    const session: LogtoTokenSession = {
      refreshToken: 'rt_seed',
      idToken: 'id_seed',
      accessTokens: { 'https://api.example.com': cached },
    };
    const { provider } = await makeProviderAsync({ session });

    // Act
    const token = await provider.getAccessToken('https://api.example.com').unwrap();

    // Assert
    should(token.token).equal('at_cached');
    should(tokenCalls).equal(0);
  });

  it('refreshes when the cached token is within the expiry skew', async () => {
    // Arrange
    const nearlyExpired = { token: 'at_cached', expiresAt: FIXED_NOW.add({ seconds: 10 }) };
    const session: LogtoTokenSession = {
      refreshToken: 'rt_seed',
      accessTokens: { 'https://api.example.com': nearlyExpired },
    };
    const { provider, storage } = await makeProviderAsync({ session });

    // Act
    const token = await provider.getAccessToken('https://api.example.com').unwrap();

    // Assert
    should(token.token).equal('at_next');
    should(tokenCalls).equal(1);
    should(lastGrantType).equal('refresh_token');
    should((await storage.get().unwrap())?.refreshToken).equal('rt_next');
  });

  it('rejects a blank resource', async () => {
    // Arrange
    const { provider } = await makeProviderAsync({ session: { refreshToken: 'rt_seed', accessTokens: {} } });

    // Act
    const result = provider.getAccessToken('   ');

    // Assert
    should(await result.isErr()).be.true();
    should(tokenCalls).equal(0);
  });

  it('rejects a non-URL resource through Zod safeParse', async () => {
    // Arrange
    const { provider } = await makeProviderAsync({ session: { refreshToken: 'rt_seed', accessTokens: {} } });

    // Act
    const result = provider.getAccessToken('zinc-api');

    // Assert
    should(await result.isErr()).be.true();
    should(tokenCalls).equal(0);
  });

  it('serializes concurrent audience refreshes so each grant uses the rotated token', async () => {
    // Arrange
    const storage = new InMemoryStorage({ refreshToken: 'rt_seed', accessTokens: {} });
    const refreshTokens: string[] = [];
    let activeRequests = 0;
    let maxActiveRequests = 0;
    let sequence = 0;
    const fetchLike: LogtoFetchLike = async (input, init) => {
      const request = input instanceof Request ? new Request(input, init) : new Request(input.toString(), init);
      const parameters = new URLSearchParams(await request.text());
      const refreshToken = parameters.get('refresh_token') ?? '';
      refreshTokens.push(refreshToken);
      activeRequests += 1;
      maxActiveRequests = Math.max(maxActiveRequests, activeRequests);
      try {
        await new Promise(resolve => setTimeout(resolve, 10));
        const expected = sequence === 0 ? 'rt_seed' : `rt_${sequence}`;
        if (refreshToken !== expected) {
          return Response.json({ error: 'invalid_grant' }, { status: 400 });
        }
        sequence += 1;
        return Response.json({
          access_token: `at_${sequence}`,
          refresh_token: `rt_${sequence}`,
          expires_in: 600,
        });
      } finally {
        activeRequests -= 1;
      }
    };
    const provider = await createLogtoAuthProvider({
      endpoint: baseUrl,
      appId: APP_ID,
      appSecret: APP_SECRET,
      storage,
      problems,
      clock: fixedClock(),
      fetch: fetchLike,
    }).unwrap();

    // Act
    const results = await Promise.all([
      provider.getAccessToken('https://zinc.example.com').serial(),
      provider.getAccessToken('https://argon.example.com').serial(),
    ]);

    // Assert
    should(results.map(result => result[0])).deepEqual(['ok', 'ok']);
    should(maxActiveRequests).equal(1);
    should(refreshTokens).deepEqual(['rt_seed', 'rt_1']);
    const session = await storage.get().unwrap();
    should(session?.refreshToken).equal('rt_2');
    should(session?.accessTokens['https://zinc.example.com']?.token).equal('at_1');
    should(session?.accessTokens['https://argon.example.com']?.token).equal('at_2');
  });
});

describe('LogtoAuthProvider — refresh rotation', () => {
  it('rotates to the new refresh token and never reuses the old one', async () => {
    // Arrange
    const session: LogtoTokenSession = { refreshToken: 'rt_old', idToken: 'id_old', accessTokens: {} };
    const { provider, storage } = await makeProviderAsync({ session });

    // Act
    const refreshed = provider.refresh();

    // Assert
    should(await refreshed.isOk()).be.true();
    should(lastRefreshTokenSent).equal('rt_old');
    should((await storage.get().unwrap())?.refreshToken).equal('rt_next');
  });

  it('fails typed, revokes, and clears the session when no replacement refresh token is returned', async () => {
    // Arrange
    refreshReply = { status: 200, body: { access_token: 'at_next', scope: 'openid', expires_in: 600 } };
    const session: LogtoTokenSession = { refreshToken: 'rt_old', accessTokens: {} };
    const { provider, storage } = await makeProviderAsync({ session });

    // Act
    const refreshed = provider.refresh();

    // Assert
    should(await refreshed.isErr()).be.true();
    should((await refreshed.unwrapErr()).status).equal(502);
    should(revokedTokens).containEql('rt_old');
    should(await storage.get().unwrap()).be.undefined();
  });

  it('treats a blank replacement refresh token as a rotation failure', async () => {
    // Arrange
    refreshReply = {
      status: 200,
      body: { access_token: 'at_next', refresh_token: '   ', scope: 'openid', expires_in: 600 },
    };
    const session: LogtoTokenSession = { refreshToken: 'rt_old', accessTokens: {} };
    const { provider, storage } = await makeProviderAsync({ session });

    // Act
    const refreshed = provider.refresh();

    // Assert
    should(await refreshed.isErr()).be.true();
    should(revokedTokens).containEql('rt_old');
    should(await storage.get().unwrap()).be.undefined();
  });

  it('stays fail-closed and clears tokens on invalid_grant', async () => {
    // Arrange
    refreshReply = { status: 400, body: { error: 'invalid_grant', error_description: 'token already used' } };
    const session: LogtoTokenSession = { refreshToken: 'rt_stolen', accessTokens: {} };
    const { provider, storage } = await makeProviderAsync({ session });

    // Act
    const refreshed = provider.refresh();

    // Assert
    should(await refreshed.isErr()).be.true();
    should((await refreshed.unwrapErr()).status).equal(401);
    should(await storage.get().unwrap()).be.undefined();
  });

  it('revokes the replacement and clears storage when a rotated response has no usable access token', async () => {
    // Arrange
    refreshReply = {
      status: 200,
      body: { access_token: '   ', refresh_token: 'rt_replacement', scope: 'openid', expires_in: 600 },
    };
    const session: LogtoTokenSession = { refreshToken: 'rt_consumed', accessTokens: {} };
    const { provider, storage } = await makeProviderAsync({ session });

    // Act
    const refreshed = await provider.refresh().serial();

    // Assert
    should(refreshed[0]).equal('err');
    should(lastRefreshTokenSent).equal('rt_consumed');
    should(revokedTokens).containEql('rt_replacement');
    should(await storage.get().unwrap()).be.undefined();
  });

  it('revokes the replacement and clears storage when rotated-session persistence fails', async () => {
    // Arrange
    const failure = storageFailure();
    const storage = new FailingSetStorage({ refreshToken: 'rt_consumed', accessTokens: {} }, failure);
    const provider = await createLogtoAuthProvider({
      endpoint: baseUrl,
      appId: APP_ID,
      appSecret: APP_SECRET,
      storage,
      problems,
      clock: fixedClock(),
    }).unwrap();

    // Act
    const refreshed = await provider.refresh().serial();

    // Assert
    should(refreshed).deepEqual(['err', failure]);
    should(lastRefreshTokenSent).equal('rt_consumed');
    should(revokedTokens).containEql('rt_next');
    should(storage.clearCalls).equal(1);
    should(storage.session).be.undefined();
  });

  it('revokes the replacement and clears when a rotated response fails schema validation', async () => {
    // Arrange — a present-but-malformed response (non-numeric expiry) after the old token is consumed.
    refreshReply = {
      status: 200,
      body: { access_token: 'at_next', refresh_token: 'rt_bad_replacement', scope: 'openid', expires_in: 'soon' },
    };
    const session: LogtoTokenSession = { refreshToken: 'rt_consumed', accessTokens: {} };
    const { provider, storage } = await makeProviderAsync({ session });

    // Act
    const refreshed = await provider.refresh().serial();

    // Assert
    should(refreshed[0]).equal('err');
    should(lastRefreshTokenSent).equal('rt_consumed');
    should(revokedTokens).containEql('rt_bad_replacement');
    should(await storage.get().unwrap()).be.undefined();
  });

  it('defaults expiry to the ten-minute lifetime when the SDK omits expires_in', async () => {
    // Arrange
    refreshReply = { status: 200, body: { access_token: 'at_next', refresh_token: 'rt_next', scope: 'openid' } };
    const { provider } = await makeProviderAsync({
      session: { refreshToken: 'rt_old', accessTokens: {} },
      clock: fixedClock(),
    });

    // Act
    const token = await provider.getAccessToken('https://api.example.com').unwrap();

    // Assert
    should(token.expiresAt.equals(FIXED_NOW.add({ minutes: 10 }))).be.true();
  });

  it('surfaces Unauthorized when no refresh token is available', async () => {
    // Arrange
    const { provider } = await makeProviderAsync({ session: { refreshToken: '   ', accessTokens: {} } });

    // Act
    const refreshed = provider.refresh();

    // Assert
    should(await refreshed.isErr()).be.true();
    should((await refreshed.unwrapErr()).status).equal(401);
    should(tokenCalls).equal(0);
  });
});

describe('LogtoAuthProvider — ten-minute access-token contract', () => {
  it('caps an over-long SDK expires_in at the fixed ten-minute lifetime', async () => {
    // Arrange
    refreshReply = {
      status: 200,
      body: { access_token: 'at_next', refresh_token: 'rt_next', scope: 'openid', expires_in: 3600 },
    };
    const { provider } = await makeProviderAsync({
      session: { refreshToken: 'rt_old', accessTokens: {} },
      clock: fixedClock(),
    });

    // Act
    const token = await provider.getAccessToken('https://api.example.com').unwrap();

    // Assert
    should(token.expiresAt.equals(FIXED_NOW.add({ minutes: 10 }))).be.true();
  });

  it('honours a shorter SDK expires_in without extending it', async () => {
    // Arrange
    refreshReply = {
      status: 200,
      body: { access_token: 'at_next', refresh_token: 'rt_next', scope: 'openid', expires_in: 120 },
    };
    const { provider } = await makeProviderAsync({
      session: { refreshToken: 'rt_old', accessTokens: {} },
      clock: fixedClock(),
    });

    // Act
    const token = await provider.getAccessToken('https://api.example.com').unwrap();

    // Assert
    should(token.expiresAt.equals(FIXED_NOW.add({ seconds: 120 }))).be.true();
  });
});

describe('LogtoAuthProvider — id token and sign-in URL', () => {
  it('returns the stored id token', async () => {
    // Arrange
    const { provider } = await makeProviderAsync({
      session: { refreshToken: 'rt', idToken: 'id_stored', accessTokens: {} },
    });

    // Act
    const idToken = await provider.getIdToken().unwrap();

    // Assert
    should(idToken).equal('id_stored');
  });

  it('returns Unauthorized when no id token is stored', async () => {
    // Arrange
    const { provider } = await makeProviderAsync({ session: { refreshToken: 'rt', accessTokens: {} } });

    // Act
    const result = provider.getIdToken();

    // Assert
    should(await result.isErr()).be.true();
    should((await result.unwrapErr()).status).equal(401);
  });

  it('builds a Logto sign-in URI via the SDK', async () => {
    // Arrange
    const { provider } = await makeProviderAsync({ session: { refreshToken: 'rt', accessTokens: {} } });

    // Act
    const uri = await provider
      .signInUrl({
        redirectUri: 'https://app.example.com/callback',
        state: 'state123',
        codeChallenge: 'challenge123',
        scopes: ['profile'],
        resources: ['https://api.example.com'],
      })
      .unwrap();

    // Assert
    const parsed = new URL(uri);
    should(parsed.pathname).equal('/oidc/auth');
    should(parsed.searchParams.get('client_id')).equal(APP_ID);
    should(parsed.searchParams.get('state')).equal('state123');
    should(parsed.searchParams.get('code_challenge')).equal('challenge123');
    should(parsed.searchParams.get('redirect_uri')).equal('https://app.example.com/callback');
  });

  it('rejects invalid public sign-in coordinates through Zod safeParse', async () => {
    // Arrange
    const { provider } = await makeProviderAsync({ session: { refreshToken: 'rt', accessTokens: {} } });

    // Act
    const result = provider.signInUrl({
      redirectUri: '//evil.invalid/callback',
      state: ' ',
      codeChallenge: '',
      prompt: 'unsupported',
    });

    // Assert
    should(await result.isErr()).be.true();
    should((await result.unwrapErr()).status).equal(502);
  });

  it('prevents extra parameters from overriding reserved OAuth coordinates', async () => {
    // Arrange
    const { provider } = await makeProviderAsync({ session: { refreshToken: 'rt', accessTokens: {} } });

    // Act
    const result = provider.signInUrl({
      redirectUri: 'https://app.example.com/callback',
      state: 'state123',
      codeChallenge: 'challenge123',
      extraParameters: { redirect_uri: 'https://evil.invalid/callback' },
    });

    // Assert
    should(await result.isErr()).be.true();
  });
});

describe('LogtoAuthProvider — clearTokens', () => {
  it('drops cached access tokens while retaining the refresh session', async () => {
    // Arrange
    const session: LogtoTokenSession = {
      refreshToken: 'rt_keep',
      idToken: 'id_keep',
      accessTokens: { 'https://api.example.com': { token: 'at', expiresAt: FIXED_NOW.add({ minutes: 5 }) } },
    };
    const { provider, storage } = await makeProviderAsync({ session });

    // Act
    const cleared = provider.clearTokens();

    // Assert
    should(await cleared.isOk()).be.true();
    const after = await storage.get().unwrap();
    should(after?.refreshToken).equal('rt_keep');
    should(after?.idToken).equal('id_keep');
    should(Object.keys(after?.accessTokens ?? {})).have.length(0);
  });
});
