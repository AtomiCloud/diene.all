import { afterEach, describe, expect, it } from 'bun:test';
import { buildWorld } from '../../bin/releaser';
import { GitHubApi } from '../../src/adapters/github/github-api';
import type { GitHubReleaseRequest } from '../../src/lib/release/ports';

const servers: Bun.Server<unknown>[] = [];

afterEach(() => {
  for (const server of servers.splice(0)) server.stop();
});

function releaseRequest(overrides: Partial<GitHubReleaseRequest> = {}): GitHubReleaseRequest {
  return {
    repository: 'AtomiCloud/example',
    tag: 'v1.0.0',
    version: '1.0.0',
    notes: 'notes',
    commits: [],
    successComment: 'Released in 1.0.0.',
    releasedLabels: ['released'],
    ...overrides,
  };
}

describe('GitHub API adapter', () => {
  it('should create a release, deduplicate closing issues and associated PRs, then comment and label', async () => {
    // Arrange
    const requests: Array<{ path: string; method: string; body: unknown }> = [];
    const server = Bun.serve({
      port: 0,
      async fetch(request) {
        const url = new URL(request.url);
        const body = request.method === 'GET' ? null : await request.json();
        requests.push({ path: url.pathname, method: request.method, body });
        if (url.pathname.endsWith('/pulls')) return Response.json([{ number: 8 }, { number: 7 }]);
        return Response.json({ ok: true });
      },
    });
    servers.push(server);
    const subject = new GitHubApi('secret-token', `http://127.0.0.1:${server.port}`);

    // Act
    await subject.publishRelease(
      releaseRequest({
        commits: [{ sha: 'a'.repeat(40), message: 'fix: repair\n\nFixes #7' }],
      }),
    );

    // Assert
    expect(requests[0]).toMatchObject({ path: '/repos/AtomiCloud/example/releases', method: 'POST' });
    expect(requests.filter(item => item.path.endsWith('/comments')).map(item => item.path)).toEqual([
      '/repos/AtomiCloud/example/issues/7/comments',
      '/repos/AtomiCloud/example/issues/8/comments',
    ]);
    expect(requests.filter(item => item.path.endsWith('/labels'))).toHaveLength(2);
  });

  it('should keep the production composition root pinned to the official API base', () => {
    const world = buildWorld(process.cwd(), {
      GITHUB_TOKEN: 'secret-token',
      RELEASER_GITHUB_API_URL: 'http://127.0.0.1:1',
    });
    expect((world.github as unknown as { baseUrl: string }).baseUrl).toBe('https://api.github.com');
  });

  it('should redact tokens from transport, 4xx, and 5xx failures and reject missing credentials', async () => {
    // Arrange
    const failingFetch = (() => Promise.reject(new Error('secret-token leaked'))) as unknown as typeof fetch;
    const failing = new GitHubApi('secret-token', 'http://example.invalid', failingFetch);
    const missing = new GitHubApi(undefined);
    const request = releaseRequest();

    // Act / Assert
    await expect(failing.publishRelease(request)).rejects.toThrow('[redacted]');
    await expect(failing.publishRelease(request)).rejects.not.toThrow('secret-token');
    await expect(missing.publishRelease(request)).rejects.toThrow('GITHUB_TOKEN');
    for (const status of [400, 500]) {
      const responseFetch = (() =>
        Promise.resolve(new Response(`secret-token status ${status}`, { status }))) as unknown as typeof fetch;
      const subject = new GitHubApi('secret-token', 'http://example.invalid', responseFetch);
      await expect(subject.publishRelease(request)).rejects.toThrow(String(status));
      await expect(subject.publishRelease(request)).rejects.toThrow('[redacted]');
      await expect(subject.publishRelease(request)).rejects.not.toThrow('secret-token');
    }
  });

  it('should reject invalid JSON and declared or streamed oversized responses', async () => {
    const invalidJson = new GitHubApi('secret-token', 'http://example.invalid', (() =>
      Promise.resolve(new Response('not-json'))) as unknown as typeof fetch);
    const declaredOversize = new GitHubApi('secret-token', 'http://example.invalid', (() =>
      Promise.resolve(
        new Response('{}', { headers: { 'content-length': String(1024 * 1024 + 1) } }),
      )) as unknown as typeof fetch);
    const streamedOversize = new GitHubApi('secret-token', 'http://example.invalid', (() =>
      Promise.resolve(
        new Response(
          new ReadableStream<Uint8Array>({
            start(controller) {
              controller.enqueue(new Uint8Array(600 * 1024));
              controller.enqueue(new Uint8Array(600 * 1024));
              controller.close();
            },
          }),
        ),
      )) as unknown as typeof fetch);

    await expect(invalidJson.publishRelease(releaseRequest())).rejects.toThrow('invalid JSON');
    await expect(declaredOversize.publishRelease(releaseRequest())).rejects.toThrow('too large');
    await expect(streamedOversize.publishRelease(releaseRequest())).rejects.toThrow('too large');
  });

  it('should enforce request timeout and validate repository and SHA before any request', async () => {
    const timeoutFetch = ((_input: string | URL | Request, init?: RequestInit) =>
      new Promise<Response>((_resolve, reject) => {
        const signal = init?.signal;
        if (signal === null || signal === undefined) {
          reject(new Error('missing timeout signal'));
          return;
        }
        if (signal.aborted) {
          reject(signal.reason);
          return;
        }
        signal.addEventListener('abort', () => reject(signal.reason), { once: true });
      })) as typeof fetch;
    const timeout = new GitHubApi('secret-token', 'http://example.invalid', timeoutFetch, 5);
    await expect(timeout.publishRelease(releaseRequest())).rejects.toThrow('GitHub API POST');

    let requests = 0;
    const countingFetch = (() => {
      requests += 1;
      return Promise.resolve(Response.json({ ok: true }));
    }) as unknown as typeof fetch;
    const validating = new GitHubApi('secret-token', 'http://example.invalid', countingFetch);
    await expect(validating.publishRelease(releaseRequest({ repository: 'owner/../repository' }))).rejects.toThrow(
      'repository identity',
    );
    await expect(
      validating.publishRelease(releaseRequest({ commits: [{ sha: 'not-a-sha', message: 'fix: repair' }] })),
    ).rejects.toThrow('commit SHA');
    expect(requests).toBe(0);
  });
});
