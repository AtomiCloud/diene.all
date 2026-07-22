import { GitHubError } from '../../lib/errors';
import type { GitHubReleaseRequest, IGitHub } from '../../lib/release/ports';

const MAX_RESPONSE_BYTES = 1024 * 1024;
const OWNER = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$/;
const REPOSITORY = /^[A-Za-z0-9._-]{1,100}$/;
const COMMIT_SHA = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/i;

function redact(value: string, token: string): string {
  return value.replaceAll(token, '[redacted]');
}

function repositoryPath(identity: string): string {
  const parts = identity.split('/');
  if (parts.length !== 2) throw new GitHubError('invalid GitHub repository identity');
  const [owner, repository] = parts;
  if (
    owner === undefined ||
    repository === undefined ||
    !OWNER.test(owner) ||
    !REPOSITORY.test(repository) ||
    repository === '.' ||
    repository === '..'
  ) {
    throw new GitHubError('invalid GitHub repository identity');
  }
  return `${encodeURIComponent(owner)}/${encodeURIComponent(repository)}`;
}

function commitPath(sha: string): string {
  if (!COMMIT_SHA.test(sha)) throw new GitHubError(`invalid Git commit SHA: ${JSON.stringify(sha)}`);
  return encodeURIComponent(sha);
}

async function readBoundedResponse(response: Response, method: string, path: string, token: string): Promise<string> {
  const declared = response.headers.get('content-length');
  if (declared !== null && /^\d+$/.test(declared) && Number(declared) > MAX_RESPONSE_BYTES) {
    throw new GitHubError(`GitHub API ${method} ${path} response is too large`);
  }
  if (response.body === null) return '';

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const result = await reader.read();
      if (result.done) break;
      const chunk = result.value;
      total += chunk.byteLength;
      if (total > MAX_RESPONSE_BYTES) {
        await reader.cancel('response exceeded the one-MiB limit').catch(() => undefined);
        throw new GitHubError(`GitHub API ${method} ${path} response is too large`);
      }
      chunks.push(chunk);
    }
  } catch (error) {
    if (error instanceof GitHubError) throw error;
    throw new GitHubError(`GitHub API ${method} ${path} response read failed: ${redact(String(error), token)}`);
  } finally {
    reader.releaseLock();
  }

  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(bytes);
}

async function requestJson(
  fetcher: typeof fetch,
  baseUrl: string,
  token: string,
  timeoutMs: number,
  method: string,
  path: string,
  body?: unknown,
): Promise<unknown> {
  let response: Response;
  try {
    response = await fetcher(`${baseUrl}${path}`, {
      method,
      headers: {
        Accept: 'application/vnd.github+json',
        Authorization: `Bearer ${token}`,
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'releaser',
        ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (error) {
    throw new GitHubError(`GitHub API ${method} ${path} failed: ${redact(String(error), token)}`);
  }
  const text = await readBoundedResponse(response, method, path, token);
  if (!response.ok) {
    throw new GitHubError(
      `GitHub API ${method} ${path} failed with ${response.status}: ${redact(text.slice(0, 500), token)}`,
    );
  }
  if (text.length === 0) return null;
  try {
    return JSON.parse(text);
  } catch {
    throw new GitHubError(`GitHub API ${method} ${path} returned invalid JSON`);
  }
}

function closingReferences(commits: readonly { readonly message: string }[]): number[] {
  const numbers = new Set<number>();
  const pattern = /\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#(\d+)\b/gi;
  for (const commit of commits) {
    for (const match of commit.message.matchAll(pattern)) {
      const number = Number(match[1]);
      if (Number.isSafeInteger(number) && number > 0) numbers.add(number);
    }
  }
  return [...numbers];
}

export class GitHubApi implements IGitHub {
  constructor(
    private readonly token: string | undefined,
    private readonly baseUrl = 'https://api.github.com',
    private readonly fetcher: typeof fetch = fetch,
    private readonly timeoutMs = 10_000,
  ) {}

  async publishRelease(request: GitHubReleaseRequest): Promise<void> {
    if (this.token === undefined || this.token.trim().length === 0) {
      throw new GitHubError('GITHUB_TOKEN is required when release.github is enabled');
    }
    const repository = repositoryPath(request.repository);
    const commits = request.commits.map(commit => ({ commit, path: commitPath(commit.sha) }));
    await requestJson(this.fetcher, this.baseUrl, this.token, this.timeoutMs, 'POST', `/repos/${repository}/releases`, {
      tag_name: request.tag,
      name: request.version,
      body: request.notes,
    });

    const affected = new Set(closingReferences(request.commits));
    for (const { path } of commits) {
      const response = await requestJson(
        this.fetcher,
        this.baseUrl,
        this.token,
        this.timeoutMs,
        'GET',
        `/repos/${repository}/commits/${path}/pulls`,
      );
      if (Array.isArray(response)) {
        for (const pull of response) {
          const number = (pull as { number?: unknown }).number;
          if (typeof number === 'number' && Number.isSafeInteger(number) && number > 0) affected.add(number);
        }
      }
    }

    for (const number of [...affected].sort((left, right) => left - right)) {
      await requestJson(
        this.fetcher,
        this.baseUrl,
        this.token,
        this.timeoutMs,
        'POST',
        `/repos/${repository}/issues/${number}/comments`,
        { body: request.successComment },
      );
      if (request.releasedLabels.length > 0) {
        await requestJson(
          this.fetcher,
          this.baseUrl,
          this.token,
          this.timeoutMs,
          'POST',
          `/repos/${repository}/issues/${number}/labels`,
          { labels: request.releasedLabels },
        );
      }
    }
  }
}
