import { describe, it } from 'bun:test';
import should from 'should';
import { z } from 'zod';
import {
  createProblem,
  type ErrorPortalConfig,
  fromError,
  fromHttpError,
  isProblem,
  ProblemRegistry,
  ProblemTransformer,
} from '../../src/index.js';

const portal: ErrorPortalConfig = {
  scheme: 'https',
  host: 'errors.atomi.cloud',
  landscape: 'raichu',
  platform: 'nitroso',
  service: 'zinc',
  module: 'api',
};

function fixture() {
  const registry = new ProblemRegistry(portal);
  const fallback = registry.register({
    id: 'unexpected_error',
    title: 'Unexpected Error',
    status: 500,
    version: 'v1',
    dataSchema: z.object({ source: z.string() }),
  });
  const transformer = new ProblemTransformer({
    fallback,
    fallbackData: value => ({ source: typeof value }),
    instance: () => '/operation/42',
  });
  return { fallback, transformer };
}

describe('ProblemTransformer.fromError', () => {
  it('should preserve Problems and unwrap nested errors', () => {
    // Arrange
    const { fallback, transformer } = fixture();
    const problem = createProblem(fallback, { detail: 'already mapped', data: { source: 'mapped' } });

    // Act
    const preserved = transformer.fromError(problem);
    const nested = transformer.fromError({ error: new Error('nested failure') });

    // Assert
    should(preserved).equal(problem);
    should(nested.detail).equal('nested failure');
    should(nested.instance).equal('/operation/42');
    should(isProblem(preserved)).be.true();
    should(isProblem(null)).be.false();
  });

  it('should normalize Error, string, record, and unknown inputs through the fallback definition', () => {
    // Arrange
    const { fallback, transformer } = fixture();

    // Act
    const error = fromError(new Error('boom'), transformer.options);
    const text = transformer.fromError('plain failure');
    const detail = transformer.fromError({ detail: 'detail failure' });
    const message = transformer.fromError({ message: 'message failure' });
    const unknown = transformer.fromError(42);

    // Assert
    should(error.type).equal(fallback.type);
    should(text.detail).equal('plain failure');
    should(detail.detail).equal('detail failure');
    should(message.detail).equal('message failure');
    should(unknown.detail).equal('An unexpected error occurred');
  });

  it('should terminate nested error cycles at the fallback definition', () => {
    // Arrange
    const { fallback, transformer } = fixture();
    const self: { error?: unknown } = {};
    self.error = self;
    const first: { error?: unknown; message: string } = { message: 'first' };
    const second: { error?: unknown; message: string } = { message: 'second' };
    first.error = second;
    second.error = first;

    // Act
    const selfCycle = transformer.fromError(self);
    const twoObjectCycle = transformer.fromError(first);

    // Assert
    should(selfCycle.type).equal(fallback.type);
    should(twoObjectCycle.type).equal(fallback.type);
    should(twoObjectCycle.detail).equal('second');
  });
});

describe('ProblemTransformer.fromHttpError', () => {
  it('should parse direct and nested RFC 9457 response bodies with the transport status', async () => {
    // Arrange
    const { fallback, transformer } = fixture();
    const problem = createProblem(fallback, { data: { source: 'remote' } });

    // Act
    const direct = await transformer.fromHttpError(
      new Response(JSON.stringify(problem), { status: 503, headers: { 'content-type': 'application/problem+json' } }),
    );
    const nested = await fromHttpError(new Response(JSON.stringify({ problem }), { status: 502 }), transformer.options);

    // Assert
    should(direct.status).equal(503);
    should(nested.status).equal(502);
    should(direct.data).eql({ source: 'remote' });
  });

  it('should map JSON, text, and empty HTTP errors through the fallback', async () => {
    // Arrange
    const { transformer } = fixture();
    const located = new Response(JSON.stringify({ message: 'remote message' }), { status: 409 });
    Object.defineProperty(located, 'url', { value: 'https://api.example/notes/42' });

    // Act
    const json = await transformer.fromHttpError(located);
    const text = await transformer.fromHttpError(new Response('plain response', { status: 500 }));
    const empty = await transformer.fromHttpError(new Response(null, { status: 504, statusText: 'Gateway Timeout' }));

    // Assert
    should(json.detail).equal('remote message');
    should(json.instance).equal('https://api.example/notes/42');
    should(text.detail).equal('plain response');
    should(empty.detail).equal('Gateway Timeout');
  });
});
