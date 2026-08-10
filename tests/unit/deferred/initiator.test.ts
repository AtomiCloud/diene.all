import { describe, it } from 'bun:test';
import { Temporal } from '@js-temporal/polyfill';
import should from 'should';
import { type FetchLike, initiateHandoff } from '../../../src/lib/deferred/initiator';
import { testAuthProblems } from './support';

const problems = testAuthProblems();

interface Captured {
  url: string;
  init: RequestInit | undefined;
}

function capturingFetch(responder: () => Response | Promise<Response>): { fetch: FetchLike; captured: Captured[] } {
  const captured: Captured[] = [];
  const fetch: FetchLike = async (url, init) => {
    captured.push({ url, init });
    return responder();
  };
  return { fetch, captured };
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}

describe('initiateHandoff', () => {
  it('POSTs an empty bearer-authenticated body and returns the mint result', async () => {
    // Arrange
    const { fetch, captured } = capturingFetch(() =>
      jsonResponse({ nonce: 'n'.repeat(43), expiresAt: '2026-07-24T12:15:00Z' }),
    );
    const input = {
      fetch,
      baseUrl: 'https://api.example.com/',
      mount: '/app-handoff',
      accessToken: 'tok_123',
      problems,
    };

    // Act
    const actual = await initiateHandoff(input).unwrap();

    // Assert
    should(actual.nonce).equal('n'.repeat(43));
    should(actual.expiresAt.equals(Temporal.Instant.from('2026-07-24T12:15:00Z'))).be.true();
    should(captured[0]?.url).equal('https://api.example.com/app-handoff');
    should(captured[0]?.init?.method).equal('POST');
    should(captured[0]?.init?.body).equal('{}');
    should((captured[0]?.init?.headers as Record<string, string>).authorization).equal('Bearer tok_123');
  });

  it('defaults the mount to /app-handoff', async () => {
    // Arrange
    const { fetch, captured } = capturingFetch(() =>
      jsonResponse({ nonce: 'n'.repeat(43), expiresAt: '2026-07-24T12:15:00Z' }),
    );

    // Act
    await initiateHandoff({ fetch, baseUrl: 'https://api.example.com', accessToken: 't', problems }).serial();

    // Assert
    should(captured[0]?.url).equal('https://api.example.com/app-handoff');
  });

  it('rejects a blank bearer before any fetch (Unauthorized)', async () => {
    // Arrange
    const { fetch, captured } = capturingFetch(() => jsonResponse({}));
    const input = { fetch, baseUrl: 'https://api.example.com', accessToken: '   ', problems };

    // Act
    const actual = await initiateHandoff(input).unwrapErr();

    // Assert
    should(actual.status).equal(401);
    should(captured.length).equal(0);
  });

  it('rejects a blank base URL before any fetch', async () => {
    // Arrange
    const { fetch, captured } = capturingFetch(() => jsonResponse({}));
    const input = { fetch, baseUrl: '  ', accessToken: 'tok', problems };

    // Act
    const actual = await initiateHandoff(input).isErr();

    // Assert
    should(actual).be.true();
    should(captured.length).equal(0);
  });

  it('rejects a blank mount before any fetch', async () => {
    // Arrange
    const { fetch, captured } = capturingFetch(() => jsonResponse({}));
    const input = { fetch, baseUrl: 'https://api.example.com', mount: '', accessToken: 'tok', problems };

    // Act
    const actual = await initiateHandoff(input).isErr();

    // Assert
    should(actual).be.true();
    should(captured.length).equal(0);
  });

  it('rejects non-origin base URLs and unsafe mounts before any fetch', async () => {
    // Arrange
    const inputs = [
      { baseUrl: 'ftp://api.example.com', mount: '/app-handoff' },
      { baseUrl: 'https://api.example.com/base', mount: '/app-handoff' },
      { baseUrl: 'https://user:pass@api.example.com', mount: '/app-handoff' },
      { baseUrl: 'https://api.example.com?tenant=x', mount: '/app-handoff' },
      { baseUrl: 'https://api.example.com', mount: 'app-handoff' },
      { baseUrl: 'https://api.example.com', mount: '//evil.invalid' },
      { baseUrl: 'https://api.example.com', mount: '/app-handoff/../redeem' },
      { baseUrl: 'https://api.example.com', mount: '/app-handoff/%2e%2e/redeem' },
      { baseUrl: 'https://api.example.com', mount: '/app-handoff//redeem' },
      { baseUrl: 'https://api.example.com', mount: '/app-handoff?x=1' },
    ];

    // Act
    const outcomes = await Promise.all(
      inputs.map(async input => {
        const { fetch, captured } = capturingFetch(() => jsonResponse({}));
        const result = await initiateHandoff({ ...input, fetch, accessToken: 'tok', problems }).serial();
        return { result, calls: captured.length };
      }),
    );

    // Assert
    should(outcomes.every(outcome => outcome.result[0] === 'err')).be.true();
    should(outcomes.map(outcome => outcome.calls)).deepEqual(Array(inputs.length).fill(0));
  });

  it('rejects a response whose nonce is not an exact 43-char base64url string', async () => {
    // Arrange
    const { fetch } = capturingFetch(() => jsonResponse({ nonce: 'too-short', expiresAt: '2026-07-24T12:15:00Z' }));
    const input = { fetch, baseUrl: 'https://api.example.com', accessToken: 'tok', problems };

    // Act
    const actual = await initiateHandoff(input).isErr();

    // Assert
    should(actual).be.true();
  });

  it('maps a 410 to the generic AppHandoffExpired', async () => {
    // Arrange
    const { fetch } = capturingFetch(() => new Response('', { status: 410 }));

    // Act
    const actual = await initiateHandoff({
      fetch,
      baseUrl: 'https://api.example.com',
      accessToken: 't',
      problems,
    }).unwrapErr();

    // Assert
    should(actual.status).equal(410);
  });

  it('maps other HTTP failures through the transformer', async () => {
    // Arrange
    const { fetch } = capturingFetch(() => new Response('boom', { status: 503 }));

    // Act
    const actual = await initiateHandoff({
      fetch,
      baseUrl: 'https://api.example.com',
      accessToken: 't',
      problems,
    }).unwrapErr();

    // Assert
    should(actual.status).equal(503);
  });

  it('maps a transport failure to AuthRefreshFailed', async () => {
    // Arrange
    const fetch: FetchLike = async () => {
      throw new Error('network down');
    };

    // Act
    const actual = await initiateHandoff({
      fetch,
      baseUrl: 'https://api.example.com',
      accessToken: 't',
      problems,
    }).unwrapErr();

    // Assert
    should(actual.status).equal(502);
  });

  it('rejects a malformed mint response', async () => {
    // Arrange
    const { fetch } = capturingFetch(() => jsonResponse({ expiresAt: '2026-07-24T12:15:00Z' }));

    // Act
    const actual = await initiateHandoff({
      fetch,
      baseUrl: 'https://api.example.com',
      accessToken: 't',
      problems,
    }).isErr();

    // Assert
    should(actual).be.true();
  });

  it('rejects unknown fields in the mint response', async () => {
    // Arrange
    const { fetch } = capturingFetch(() =>
      jsonResponse({ nonce: 'n'.repeat(43), expiresAt: '2026-07-24T12:15:00Z', subject: 'leak' }),
    );

    // Act
    const actual = await initiateHandoff({
      fetch,
      baseUrl: 'https://api.example.com',
      accessToken: 't',
      problems,
    }).isErr();

    // Assert
    should(actual).be.true();
  });

  it('rejects a 200 response carrying an invalid expiry instant', async () => {
    // Arrange
    const { fetch } = capturingFetch(() => jsonResponse({ nonce: 'n'.repeat(43), expiresAt: 'not-an-instant' }));

    // Act
    const actual = await initiateHandoff({
      fetch,
      baseUrl: 'https://api.example.com',
      accessToken: 't',
      problems,
    }).isErr();

    // Assert
    should(actual).be.true();
  });

  it('rejects a 200 response with an unparseable body', async () => {
    // Arrange
    const { fetch } = capturingFetch(
      () => new Response('not json', { status: 200, headers: { 'content-type': 'application/json' } }),
    );

    // Act
    const actual = await initiateHandoff({
      fetch,
      baseUrl: 'https://api.example.com',
      accessToken: 't',
      problems,
    }).isErr();

    // Assert
    should(actual).be.true();
  });
});
