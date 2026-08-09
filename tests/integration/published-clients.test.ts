import { describe, it } from 'bun:test';
import type { FetchLike } from '@atomicloud/diene.e2e/api';
import { buildClaims, buildTokenSet } from '@atomicloud/diene.e2e/auth/test-helper';
import should from 'should';
import { buildPublishedClients } from '../../src/api/published-clients';
import { loadApplicationConfig } from '../../src/config/load';
import { createDomainProblems } from '../../src/domain/problems';

interface SampleBackendClient {
  get(): Promise<Response>;
}

describe('published outbound clients', () => {
  it('should refresh an expired API token and call Logto management with client credentials', async () => {
    // Arrange
    const config = await loadApplicationConfig({
      configDir: 'config',
      environment: {
        ATOMI_AUTH__LOGTO__APP_ID: 'integration-consumer',
        ATOMI_AUTH__LOGTO__APP_SECRET: 'integration-secret',
        ATOMI_AUTH__LOGTO__MANAGEMENT__CLIENT_ID: 'integration-management',
        ATOMI_AUTH__LOGTO__MANAGEMENT__CLIENT_SECRET: 'integration-secret',
      },
      prefix: 'ATOMI_',
    });
    const problems = createDomainProblems(config.errorPortal, config.transport.stream, config.errorPortal.version);
    const requests: { authorization?: string; url: string }[] = [];
    let tokenStateCalls = 0;
    let expiredTokens = buildTokenSet();
    let freshTokens = buildTokenSet();
    const fakeFetch: FetchLike = async (input, init) => {
      const url = input instanceof Request ? input.url : String(input);
      const headers = new Headers(input instanceof Request ? input.headers : init?.headers);
      requests.push({ authorization: headers.get('authorization') ?? undefined, url });
      if (url === '/api/auth/tokens') {
        tokenStateCalls += 1;
        const data = tokenStateCalls === 1 ? expiredTokens : freshTokens;
        return Response.json(['ok', { __kind: 'authed', value: { data, isAuthed: true } }]);
      }
      if (url.endsWith('/oidc/token')) return Response.json({ access_token: 'management-token' });
      if (url.includes('/api/users/worker-1')) {
        return Response.json({ isSuspended: false, primaryEmail: 'worker@atomi.cloud' });
      }
      return Response.json({ source: 'control-plane' });
    };
    const published = await buildPublishedClients(config, problems.registry, fakeFetch);
    const backend = published.api.list()[0];
    should(backend).not.equal(undefined);
    const resourceKey = backend?.resourceKey;
    if (!resourceKey) throw new Error('configured API backend did not expose a resource key');
    expiredTokens = buildTokenSet({
      accessTokenClaims: { [resourceKey]: buildClaims({ exp: Math.floor(Date.now() / 1000) - 60 }) },
    });
    freshTokens = buildTokenSet({
      accessTokenClaims: { [resourceKey]: buildClaims({ exp: Math.floor(Date.now() / 1000) + 3600 }) },
    });

    // Act
    const apiClient = await published.api.resolve<SampleBackendClient>(backend.coordinate).unwrap();
    const apiResult = await apiClient.get().unwrap();
    const user = await published.auth.getUser('worker-1').unwrap();

    // Assert
    should(apiResult).deepEqual({ source: 'control-plane' });
    should(tokenStateCalls).equal(2);
    should(requests.find(request => request.url.includes('control-plane'))?.authorization).equal(
      `Bearer ${freshTokens.accessTokens[resourceKey]}`,
    );
    should(requests.find(request => request.url.endsWith('/oidc/token'))?.authorization).startWith('Basic ');
    should(requests.find(request => request.url.includes('/api/users/worker-1'))?.authorization).equal(
      'Bearer management-token',
    );
    should(user).deepEqual({ isSuspended: false, primaryEmail: 'worker@atomi.cloud' });
  });
});
