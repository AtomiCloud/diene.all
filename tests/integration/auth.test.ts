import { beforeAll, describe, it } from 'bun:test';
import should from 'should';
import { fakeJar, mockCookies, type FakeJar } from './fixtures/cookie-jar';
import { intConfig } from './fixtures/config';
import type { RootConfig } from '../../src/adapters/server-config';

// Integration: server auth assembly FAILS CLOSED. With no session cookie the
// retriever reports the unauthed wire state, and the SSR guard sends an
// unauthenticated request to sign-in carrying returnTo (path AND query).

const SESSION_COOKIE = 'diene.auth.session';

let config: RootConfig;
let jar: FakeJar;

beforeAll(async () => {
  jar = fakeJar();
  mockCookies(jar);
  config = await intConfig('base');
});

describe('cookieTokenStorage', () => {
  it('should read back a token session it persisted through the cookie jar', async () => {
    // Arrange
    const { cookieTokenStorage } = await import('../../src/adapters/auth/session');
    const storage = cookieTokenStorage(jar as never, true);
    const session = { accessTokens: { 'diene/base/dotnet-api/api': 'token' } } as never;

    // Act
    const written = storage.set(session);
    const read = storage.get();

    // Assert
    should(await written.isOk()).be.true();
    should(await read.isOk()).be.true();
    should(await read.unwrapOr(undefined)).deepEqual(session);
  });

  it('should treat an unparseable cookie as no session rather than throwing', async () => {
    // Arrange
    const { cookieTokenStorage } = await import('../../src/adapters/auth/session');
    const corrupt = fakeJar({ [SESSION_COOKIE]: '{not json' });

    // Act
    const read = cookieTokenStorage(corrupt as never, true).get();

    // Assert
    should(await read.isOk()).be.true();
    should(await read.unwrapOr('sentinel' as never)).equal(undefined);
  });

  it('should clear the session cookie', async () => {
    // Arrange
    const { cookieTokenStorage } = await import('../../src/adapters/auth/session');
    const seeded = fakeJar({ [SESSION_COOKIE]: '{}' });
    const storage = cookieTokenStorage(seeded as never, false);

    // Act
    const cleared = storage.clear();

    // Assert
    should(await cleared.isOk()).be.true();
    should(seeded.get(SESSION_COOKIE)).equal(undefined);
  });
});

describe('hasSessionCookie', () => {
  const cases: { label: string; seed: Record<string, string>; expected: boolean }[] = [
    { label: 'no cookie at all', seed: {}, expected: false },
    { label: 'an empty cookie value', seed: { [SESSION_COOKIE]: '' }, expected: false },
    { label: 'a populated cookie', seed: { [SESSION_COOKIE]: '{}' }, expected: true },
  ];
  it.each(cases)('should report $expected for $label', async ({ seed, expected }) => {
    // Arrange
    const { hasSessionCookie } = await import('../../src/adapters/auth/session');

    // Act
    const actual = hasSessionCookie(fakeJar(seed) as never);

    // Assert
    should(actual).equal(expected);
  });
});

describe('serverAuth', () => {
  it('should assemble the provider, problem set, and retriever from config', async () => {
    // Arrange
    const { serverAuth } = await import('../../src/adapters/auth/server');

    // Act
    const assembled = await (await serverAuth(config, 'base')).serial();

    // Assert
    should(assembled[0]).equal('ok');
    if (assembled[0] !== 'ok') return;
    should(assembled[1].provider).be.ok();
    should(assembled[1].retriever).be.ok();
    should(assembled[1].problems.Unauthorized).be.ok();
  });

  it('should derive one canonical resource audience per configured backend', async () => {
    // Arrange — the shipped config registers no backends, so a config carrying one
    // proves the audience map: the canonical key (platform/landscape/service/name)
    // maps to the backend's baseUrl, which is the audience sent to the issuer on a
    // token exchange. A local issuer fixture records what it was asked for.
    const exchanged: string[] = [];
    const issuer = Bun.serve({
      port: 0,
      fetch: async request => {
        if (request.method === 'POST') exchanged.push(await request.text());
        return Response.json({ access_token: 'access', expires_in: 3600, token_type: 'Bearer' });
      },
    });
    const auth = config.get('auth');
    const withBackend = {
      get: (block: string) =>
        block === 'backends'
          ? { api: { baseUrl: 'https://api.test', platform: 'diene', service: 'dotnet-api', module: 'api' } }
          : block === 'auth'
            ? { ...auth, logto: { ...auth.logto, endpoint: `http://127.0.0.1:${issuer.port}` } }
            : config.get(block as never),
    } as unknown as RootConfig;
    jar.set(SESSION_COOKIE, JSON.stringify({ refreshToken: 'refresh-token', accessTokens: {} }));
    const { serverAuth } = await import('../../src/adapters/auth/server');
    const assembled = await serverAuth(withBackend, 'lapras');

    // Act — a token exchange sends the audience map to the issuer.
    await assembled.andThen(({ retriever }) => retriever.getStates()).serial();

    // Assert — the audience the issuer was asked for is the configured backend's
    // baseUrl, so the map is composed from config rather than hardcoded.
    const exchange = new URLSearchParams(exchanged[0] ?? '');
    should(exchange.get('resource')).equal('https://api.test');
    should(exchange.get('grant_type')).equal('refresh_token');
    jar.delete(SESSION_COOKIE);
    issuer.stop(true);
  });

  it('should fail closed with the unauthed wire state when no session cookie exists', async () => {
    // Arrange — the shared jar carries no session cookie for this assertion.
    jar.delete(SESSION_COOKIE);
    const { serverAuth } = await import('../../src/adapters/auth/server');

    // Act
    const state = await (await serverAuth(config, 'base')).andThen(({ retriever }) => retriever.getClaims()).serial();

    // Assert — unauthed, never a claim payload.
    should(state[0]).equal('ok');
    if (state[0] !== 'ok') return;
    should(state[1].__kind).equal('unauthed');
    should(state[1].value.isAuthed).be.false();
  });
});

describe('requireSession', () => {
  it('should redirect an unauthenticated request to sign-in carrying returnTo with its query', async () => {
    // Arrange — next/navigation's redirect() throws a control-flow signal; capture the target.
    const { mock } = await import('bun:test');
    let redirected = '';
    mock.module('next/navigation', () => ({
      redirect: (target: string) => {
        redirected = target;
        throw new Error('NEXT_REDIRECT');
      },
    }));
    jar.delete(SESSION_COOKIE);
    const { requireSession } = await import('../../src/adapters/auth/guard');

    // Act
    const outcome = await requireSession('/reminders?filter=today').then(
      () => 'returned',
      (error: Error) => error.message,
    );

    // Assert — fail closed to login, and the whole returnTo survives.
    should(outcome).equal('NEXT_REDIRECT');
    should(redirected).startWith('/api/logto/sign-in');
    should(decodeURIComponent(redirected)).containEql('/reminders?filter=today');
  });

  it('should route a session whose claims omit the home landscape to pre-onboarding', async () => {
    // Arrange — a claims-bearing retriever is substituted for the cookie provider.
    const { mock } = await import('bun:test');
    const { authed } = await import('@atomicloud/diene.auth-engine');
    const { Ok } = await import('@atomicloud/diene.result');
    mock.module('../../src/adapters/auth/server', () => ({
      serverAuth: async () =>
        Ok({
          provider: {},
          problems: {},
          retriever: { getClaims: () => Ok(authed({ sub: 'user-1' })) },
        }),
    }));
    const { requireSession } = await import('../../src/adapters/auth/guard');

    // Act
    const session = await requireSession('/');

    // Assert
    should(session.claims.sub).equal('user-1');
    should(session.home).deepEqual({ phase: 'pre-onboarding' });
  });

  it('should route a session carrying the home landscape claim to its home landscape', async () => {
    // Arrange
    const { mock } = await import('bun:test');
    const { authed } = await import('@atomicloud/diene.auth-engine');
    const { Ok } = await import('@atomicloud/diene.result');
    mock.module('../../src/adapters/auth/server', () => ({
      serverAuth: async () =>
        Ok({
          provider: {},
          problems: {},
          retriever: { getClaims: () => Ok(authed({ sub: 'user-2', home_landscape: 'lapras' })) },
        }),
    }));
    const { requireSession } = await import('../../src/adapters/auth/guard');

    // Act
    const session = await requireSession('/');

    // Assert
    should(session.home).deepEqual({ phase: 'home', landscape: 'lapras' });
  });
});

describe('pkce', () => {
  it('should mint distinct base64url tokens with no padding', async () => {
    // Arrange
    const { randomToken } = await import('../../src/adapters/auth/pkce');

    // Act
    const first = randomToken();
    const second = randomToken();

    // Assert
    should(first).not.equal(second);
    should(first).match(/^[A-Za-z0-9_-]+$/);
  });

  it('should derive the S256 challenge for a known verifier', async () => {
    // Arrange — RFC 7636 appendix B vector.
    const { codeChallengeS256 } = await import('../../src/adapters/auth/pkce');
    const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';

    // Act
    const challenge = await codeChallengeS256(verifier);

    // Assert
    should(challenge).equal('E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
  });
});
