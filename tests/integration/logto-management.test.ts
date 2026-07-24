import { afterAll, beforeAll, describe, it } from 'bun:test';
import should from 'should';
import {
  type FetchLike,
  LogtoManagementClient,
  type LogtoManagementConfig,
  managementConfigFromAuthEngine,
} from '../../src/adapters/logto/management';
import { testAuthProblems } from '../support/auth-problems';

const problems = testAuthProblems();

const CLIENT_ID = 'm2m_client';
const CLIENT_SECRET = 'm2m_secret';
const EXPECTED_BASIC = `Basic ${btoa(`${CLIENT_ID}:${CLIENT_SECRET}`)}`;

let server: ReturnType<typeof Bun.serve> | undefined;
let baseUrl = '';
let lastMintBody: unknown;

beforeAll(() => {
  server = Bun.serve({
    port: 0,
    async fetch(request) {
      const url = new URL(request.url);

      if (url.pathname === '/oidc/token') {
        if (request.headers.get('authorization') !== EXPECTED_BASIC) {
          return Response.json({ error: 'invalid_client' }, { status: 401 });
        }
        return Response.json({ access_token: 'm2m_access_token', expires_in: 3600, token_type: 'Bearer' });
      }

      if (url.pathname.startsWith('/api/users/')) {
        const sub = decodeURIComponent(url.pathname.slice('/api/users/'.length));
        switch (sub) {
          case 'usr_ok':
            return Response.json({ id: sub, isSuspended: false, primaryEmail: 'User@Example.com' });
          case 'usr_suspended':
            return Response.json({ id: sub, isSuspended: true, primaryEmail: 'user@example.com' });
          case 'usr_null_email':
            return Response.json({ id: sub, isSuspended: false, primaryEmail: null });
          default:
            return Response.json({ message: 'not found' }, { status: 404 });
        }
      }

      if (url.pathname === '/api/one-time-tokens') {
        lastMintBody = await request.json();
        const email = (lastMintBody as { email?: string }).email;
        if (email === 'fail@example.com') {
          return Response.json({ message: 'boom' }, { status: 500 });
        }
        return Response.json({ id: 'ott_1', token: 'one_time_token_value', email });
      }

      return new Response('not found', { status: 404 });
    },
  });
  baseUrl = `http://localhost:${server.port}`;
});

afterAll(() => {
  server?.stop(true);
});

function makeClient(overrides: Partial<LogtoManagementConfig> = {}): LogtoManagementClient {
  const config: LogtoManagementConfig = {
    tokenEndpoint: `${baseUrl}/oidc/token`,
    apiBaseUrl: `${baseUrl}/api`,
    resource: `${baseUrl}/api`,
    clientId: CLIENT_ID,
    clientSecret: CLIENT_SECRET,
    scope: 'all',
    ...overrides,
  };
  return new LogtoManagementClient({ config, problems });
}

describe('LogtoManagementClient', () => {
  it('derives Management API wire config from the engine config block', () => {
    // Arrange
    const input = {
      logto: {
        endpoint: 'https://logto.example.com/',
        appId: 'app',
        appSecret: 'injected-app-secret',
        management: {
          endpoint: 'https://logto.example.com/',
          clientId: 'c',
          clientSecret: 'injected-management-secret',
        },
      },
      handoff: { mount: '/app-handoff' },
      store: { kind: 'redis' as const, host: 'localhost', port: 6379 },
    };

    // Act
    const actual = managementConfigFromAuthEngine(input);

    // Assert
    should(actual.tokenEndpoint).equal('https://logto.example.com/oidc/token');
    should(actual.apiBaseUrl).equal('https://logto.example.com/api');
    should(actual.resource).equal('https://logto.example.com/api');
  });

  it('reads an active user via the M2M-authenticated Management API', async () => {
    // Arrange
    const subject = makeClient();

    // Act
    const actual = await subject.getUser('usr_ok').unwrap();

    // Assert
    should(actual).eql({ isSuspended: false, primaryEmail: 'User@Example.com' });
  });

  it('surfaces a suspended flag without editorialising', async () => {
    // Arrange
    const subject = makeClient();

    // Act
    const actual = await subject.getUser('usr_suspended').unwrap();

    // Assert
    should(actual.isSuspended).be.true();
  });

  it('normalises a missing primary email to null', async () => {
    // Arrange
    const subject = makeClient();

    // Act
    const actual = await subject.getUser('usr_null_email').unwrap();

    // Assert
    should(actual.primaryEmail).be.null();
  });

  it('returns an error for a 404 (deleted) user', async () => {
    // Arrange
    const subject = makeClient();

    // Act
    const actual = await subject.getUser('usr_missing').isErr();

    // Assert
    should(actual).be.true();
  });

  it('mints a one-time token with the fixed 120s SignIn context', async () => {
    // Arrange
    const subject = makeClient();

    // Act
    const actual = await subject.mintOneTimeToken('user@example.com').unwrap();

    // Assert
    should(actual.token).equal('one_time_token_value');
    should(lastMintBody).eql({
      email: 'user@example.com',
      expiresIn: 120,
      context: { interactionEvent: 'SignIn' },
    });
  });

  it('returns an error when the mint endpoint fails', async () => {
    // Arrange
    const subject = makeClient();

    // Act
    const actual = await subject.mintOneTimeToken('fail@example.com').isErr();

    // Assert
    should(actual).be.true();
  });

  it('returns an error when the M2M credentials are rejected', async () => {
    // Arrange
    const subject = makeClient({ clientSecret: 'wrong_secret' });

    // Act
    const actual = await subject.getUser('usr_ok').isErr();

    // Assert
    should(actual).be.true();
  });
});

const STUB_CONFIG: LogtoManagementConfig = {
  tokenEndpoint: 'https://logto.test/oidc/token',
  apiBaseUrl: 'https://logto.test/api',
  resource: 'https://logto.test/api',
  clientId: 'c',
  clientSecret: 's',
  scope: 'all',
};

function clientWith(fetch: FetchLike): LogtoManagementClient {
  return new LogtoManagementClient({ config: STUB_CONFIG, problems, fetch });
}

function routeFetch(routes: { token?: Response; user?: Response; ott?: Response }): FetchLike {
  return async (url: string) => {
    if (url.includes('/oidc/token')) return routes.token ?? Response.json({ access_token: 'm2m' });
    if (url.includes('/users/')) return routes.user ?? Response.json({ isSuspended: false, primaryEmail: 'a@b.c' });
    if (url.includes('/one-time-tokens')) return routes.ott ?? Response.json({ token: 'ott' });
    return new Response('not found', { status: 404 });
  };
}

describe('LogtoManagementClient input + response guards', () => {
  it('preserves significant whitespace in the opaque M2M client secret', async () => {
    // Arrange
    const secret = ' management secret ';
    let authorization: string | null = null;
    const subject = new LogtoManagementClient({
      config: { ...STUB_CONFIG, clientSecret: secret },
      problems,
      fetch: async (url, init) => {
        if (url.includes('/oidc/token')) {
          authorization = new Headers(init?.headers).get('authorization');
          return Response.json({ access_token: 'm2m' });
        }
        return Response.json({ isSuspended: false, primaryEmail: 'user@example.com' });
      },
    });

    // Act
    const actual = await subject.getUser('usr_ok').isOk();

    // Assert
    should(actual).be.true();
    should(authorization).equal(`Basic ${btoa(`${STUB_CONFIG.clientId}:${secret}`)}`);
  });

  it('rejects a blank sub before acquiring a token or hitting the network (M33)', async () => {
    // Arrange
    let calls = 0;
    const subject = clientWith(async () => {
      calls += 1;
      return Response.json({ access_token: 'm2m' });
    });

    // Act
    const actual = await subject.getUser('   ').isErr();

    // Assert
    should(actual).be.true();
    should(calls).equal(0);
  });

  it('rejects a blank email before acquiring a token or hitting the network (M33)', async () => {
    // Arrange
    let calls = 0;
    const subject = clientWith(async () => {
      calls += 1;
      return Response.json({ access_token: 'm2m' });
    });

    // Act
    const actual = await subject.mintOneTimeToken('').isErr();

    // Assert
    should(actual).be.true();
    should(calls).equal(0);
  });

  it('errors when the token response omits access_token', async () => {
    // Arrange
    const subject = clientWith(routeFetch({ token: Response.json({ token_type: 'Bearer' }) }));

    // Act
    const actual = await subject.getUser('usr_ok').isErr();

    // Assert
    should(actual).be.true();
  });

  it('errors when the user response is malformed', async () => {
    // Arrange
    const subject = clientWith(routeFetch({ user: Response.json({ primaryEmail: 123 }) }));

    // Act
    const actual = await subject.getUser('usr_ok').isErr();

    // Assert
    should(actual).be.true();
  });

  it('requires an explicit suspension field in the user response', async () => {
    // Arrange
    const subject = clientWith(routeFetch({ user: Response.json({ primaryEmail: 'user@example.com' }) }));

    // Act
    const actual = await subject.getUser('usr_ok').isErr();

    // Assert
    should(actual).be.true();
  });

  it('rejects invalid Management configuration before any network call', async () => {
    // Arrange
    let calls = 0;
    const invalidConfigs: LogtoManagementConfig[] = [
      { ...STUB_CONFIG, tokenEndpoint: 'not-a-url' },
      { ...STUB_CONFIG, tokenEndpoint: 'https://user:secret@logto.test/oidc/token' },
      { ...STUB_CONFIG, apiBaseUrl: 'https://logto.test/api?tenant=other' },
      { ...STUB_CONFIG, resource: 'https://logto.test/api#other' },
    ];
    const fetch: FetchLike = async () => {
      calls += 1;
      return Response.json({ access_token: 'm2m' });
    };

    // Act
    const results = await Promise.all(
      invalidConfigs.flatMap(config => {
        const subject = new LogtoManagementClient({ config, problems, fetch });
        return [subject.getUser('usr_ok').isErr(), subject.mintOneTimeToken('user@example.com').isErr()];
      }),
    );

    // Assert
    should(results).deepEqual(Array.from({ length: invalidConfigs.length * 2 }, () => true));
    should(calls).equal(0);
  });

  it('errors when the one-time-token response omits token', async () => {
    // Arrange
    const subject = clientWith(routeFetch({ ott: Response.json({ id: 'x' }) }));

    // Act
    const actual = await subject.mintOneTimeToken('user@example.com').isErr();

    // Assert
    should(actual).be.true();
  });
});
