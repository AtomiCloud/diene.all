import { afterAll, beforeAll, describe, it, mock } from 'bun:test';
import should from 'should';
import { fakeJar, mockCookies } from './fixtures/cookie-jar';

// Integration: the deferred-login initiation route. The real dotnet-api hosts
// the mint/redeem endpoints, so the handoff host is a Bun.serve fixture; the
// route, its config wiring, and its fail-closed check are the real ones.

let host: ReturnType<typeof Bun.serve>;
let minted = 0;

const NONCE = 'a'.repeat(43);

beforeAll(() => {
  host = Bun.serve({
    port: 0,
    fetch: request => {
      const url = new URL(request.url);
      if (url.pathname === '/app-handoff' && request.method === 'POST') {
        minted += 1;
        if ((request.headers.get('authorization') ?? '') === '') {
          return Response.json({ title: 'Unauthorized', status: 401 }, { status: 401 });
        }
        return Response.json({ nonce: NONCE, expiresAt: '2030-01-01T00:00:00Z' });
      }
      return new Response('not found', { status: 404 });
    },
  });
  mockCookies(fakeJar());
});

afterAll(() => {
  host.stop(true);
});

/** Substitute the config the route reads so its handoff backend is the fixture. */
const mockConfig = (backends: Record<string, unknown>): void => {
  mock.module('../../src/adapters/server-config', () => ({
    serverLandscape: () => 'base',
    serverConfig: async () => ({
      get: (block: string) => {
        if (block === 'backends') return backends;
        if (block === 'auth') return { handoff: { mount: '/app-handoff' } };
        return {};
      },
    }),
  }));
};

const fixtureBackend = (): Record<string, unknown> => ({
  'dotnet-api': { baseUrl: `http://127.0.0.1:${host.port}`, platform: 'diene', service: 'dotnet-api', module: 'api' },
});

/** Substitute serverAuth with a retriever in the requested wire state. */
const mockAuth = async (state: 'authed' | 'unauthed'): Promise<void> => {
  const { authed, unauthed } = await import('@atomicloud/diene.auth-engine');
  const { Ok } = await import('@atomicloud/diene.result');
  mock.module('../../src/adapters/auth/server', () => ({
    serverAuth: async () =>
      Ok({
        provider: {},
        problems: { AppHandoffExpired: {}, AuthRefreshFailed: {}, Unauthorized: {} },
        retriever: {
          getTokenSet: () =>
            Ok(state === 'authed' ? authed({ accessTokens: { 'diene/base/dotnet-api/api': 'token' } }) : unauthed()),
        },
      }),
  }));
};

describe('POST /api/handoff/initiate', () => {
  it('should fail closed with 401 and never reach the handoff host when unauthenticated', async () => {
    // Arrange
    mockConfig(fixtureBackend());
    await mockAuth('unauthed');
    const before = minted;
    const { POST } = await import('../../src/app/api/handoff/initiate/route');

    // Act
    const response = await POST();

    // Assert — unauthorized, and no nonce was minted upstream.
    should(response.status).equal(401);
    should(minted).equal(before);
  });

  it('should return the nonce and the iOS clipboard carrier for an authenticated session', async () => {
    // Arrange
    mockConfig(fixtureBackend());
    await mockAuth('authed');
    const { POST } = await import('../../src/app/api/handoff/initiate/route');

    // Act
    const response = await POST();
    const body = (await response.json()) as {
      nonce: string;
      expiresAt: string;
      iosClipboardPayload: string;
    };

    // Assert
    should(response.status).equal(200);
    should(body.nonce).equal(NONCE);
    should(body.expiresAt).be.a.String();
    should(body.iosClipboardPayload).containEql(NONCE);
  });

  it('should report 501 rather than guessing a host when no dotnet-api backend is configured', async () => {
    // Arrange
    mockConfig({});
    await mockAuth('authed');
    const { POST } = await import('../../src/app/api/handoff/initiate/route');

    // Act
    const response = await POST();

    // Assert
    should(response.status).equal(501);
  });
});
