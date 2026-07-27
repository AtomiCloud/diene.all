import { createProblem } from '@atomicloud/diene.problems';
import { describe, it } from 'bun:test';
import should from 'should';
import { buildProblemRegistry } from '../../src/adapters/problem-reporter/registry';
import type { AppProblems } from '../../src/adapters/problem-reporter/registry';
import type { AppConfig, SeoConfig } from '../../src/config';

// The Problem contract: every error this service emits is an RFC 9457 envelope
// whose `type` URI addresses THIS service's error portal, and the api-engine's
// problem set is registered into that same registry so a transport failure is
// addressable by the same portal as a domain failure.

const app: AppConfig = {
  servicetree: { landscape: 'lapras', platform: 'diene', service: 'nextjs-frontend', module: 'webapp' },
};

const seo = {
  baseUrl: 'https://webapp.nextjs-frontend.diene.lapras.cluster.atomi.cloud',
} as unknown as SeoConfig;

// `unwrap` rejects on an err Result, so a failed registration fails the spec with
// the underlying Problem rather than a shape mismatch further down.
const built = (portal: SeoConfig = seo, landscape = 'lapras'): Promise<AppProblems> =>
  buildProblemRegistry(app, portal, landscape).unwrap();

const PORTAL =
  'https://webapp.nextjs-frontend.diene.lapras.cluster.atomi.cloud/docs/lapras/diene/nextjs-frontend/webapp/';

describe('buildProblemRegistry', () => {
  it('should register the api-engine problem set into the service registry', async () => {
    // Act
    const { api, registry } = await built();

    // Assert — the api set resolves out of the SAME registry the app renders
    // from, so a transport failure is not a second, unaddressable error surface.
    for (const name of [
      'ConfigurationFailure',
      'BackendNotFound',
      'AuthenticationFailure',
      'TransportFailure',
      'UpstreamFailure',
    ] as const) {
      should(api[name].id).be.a.String().and.not.empty();
      should(registry.get(api[name].id)).not.equal(undefined);
    }
  });

  it('should address every registered type URI to this service error portal', async () => {
    // Act
    const problems = (await built()).registry.list();

    // Assert — the LPSM coordinate is baked into the URI, so a Problem seen in
    // the wild names the landscape/platform/service/module that emitted it, and
    // the URI resolves to a document this service actually publishes.
    should(problems.length).be.above(0);
    for (const problem of problems) {
      should(problem.type).startWith(PORTAL);
      should(problem.type).endWith(`/${problem.version}/${problem.id}`);
    }
  });

  it('should build an RFC 9457 envelope carrying type, title, status, and data', async () => {
    // Arrange
    const definition = (await built()).api.UpstreamFailure;

    // Act
    const problem = createProblem(definition, {
      detail: 'the upstream refused',
      data: { backend: 'api', status: 502 },
    });

    // Assert — all four mandatory members present, `data` typed by the schema.
    should(problem.type).equal(definition.type);
    should(problem.title).equal(definition.title);
    should(problem.status).equal(definition.status);
    should(problem.detail).equal('the upstream refused');
    should(problem.data.backend).equal('api');
    should(problem.data.status).equal(502);
  });

  it('should derive the portal scheme from the configured base URL', async () => {
    // Arrange — a plain-http portal (local/dev landscape) must not be rewritten
    // to https, or the emitted type URIs resolve to nothing.
    const local = { baseUrl: 'http://127.0.0.1:3000' } as unknown as SeoConfig;

    // Act
    const { registry } = await built(local, 'base');

    // Assert
    should(registry.portal.scheme).equal('http');
    should(registry.portal.host).equal('127.0.0.1:3000');
  });
});
