import { z } from 'zod';
import {
  type HeaderMap,
  type IntakeFailure,
  type IntakeRequest,
  MERCURY_MAX_REQUEST_BODY_BYTES,
} from '../../domain/index.ts';
import type { IntakeEngine } from '../../runtime/index.ts';
import type { IntakeProblemCatalog } from './problems.ts';

const intakeRequestSchema = z
  .object({
    path: z.string().regex(/^\//),
    host: z.string().min(1).optional(),
    headers: z.record(z.string(), z.string()),
    rawBody: z.instanceof(Uint8Array),
  })
  .strict();

const headerMap = (headers: Headers): HeaderMap =>
  Object.fromEntries([...headers.entries()].map(([name, value]) => [name.toLowerCase(), value]));

type BoundedBodyResult =
  | Readonly<{ body: Uint8Array; kind: 'ok' }>
  | Readonly<{ kind: 'too-large' }>
  | Readonly<{ kind: 'unavailable' }>;

interface ByteStreamReader {
  cancel(reason?: unknown): Promise<void>;
  read(): Promise<Readonly<{ done: boolean; value?: Uint8Array }>>;
  releaseLock(): void;
}

const cancelStream = async (stream: ReadableStream<Uint8Array> | null, reason: unknown): Promise<void> => {
  try {
    await stream?.cancel(reason);
  } catch {
    // The response is already fail-closed; a racing peer cancellation is safe.
  }
};

const readWithCancellation = async (
  reader: ByteStreamReader,
  signal: AbortSignal,
): Promise<Readonly<{ done: boolean; value?: Uint8Array }>> => {
  if (signal.aborted) {
    throw signal.reason ?? new DOMException('request cancelled', 'AbortError');
  }
  return new Promise((resolve, reject) => {
    const cancelled = (): void => reject(signal.reason ?? new DOMException('request cancelled', 'AbortError'));
    signal.addEventListener('abort', cancelled, { once: true });
    void reader
      .read()
      .then(resolve, reject)
      .finally(() => signal.removeEventListener('abort', cancelled));
  });
};

/** Reads at most the product body limit and cancels before oversized input is materialized. */
const readBoundedRequestBody = async (
  request: Request,
  maximumBytes = MERCURY_MAX_REQUEST_BODY_BYTES,
): Promise<BoundedBodyResult> => {
  if (!Number.isSafeInteger(maximumBytes) || maximumBytes < 1) {
    throw new RangeError('request body byte limit must be a positive integer');
  }
  const declaredLength = request.headers.get('content-length');
  if (declaredLength !== null && /^\d+$/.test(declaredLength) && Number(declaredLength) > maximumBytes) {
    await cancelStream(request.body, new RangeError('request body exceeds the configured limit'));
    return { kind: 'too-large' };
  }
  if (request.body === null) return { body: new Uint8Array(), kind: 'ok' };

  let reader: ByteStreamReader;
  try {
    reader = request.body.getReader();
  } catch {
    return { kind: 'unavailable' };
  }
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;
  try {
    while (true) {
      const next = await readWithCancellation(reader, request.signal);
      if (next.done) break;
      if (!(next.value instanceof Uint8Array)) {
        await reader.cancel(new TypeError('request body stream emitted a non-byte chunk'));
        return { kind: 'unavailable' };
      }
      if (next.value.byteLength > maximumBytes - totalBytes) {
        try {
          await reader.cancel(new RangeError('request body exceeds the configured limit'));
        } catch {
          // The limit classification remains authoritative if peer cancellation races it.
        }
        return { kind: 'too-large' };
      }
      totalBytes += next.value.byteLength;
      chunks.push(next.value);
    }
  } catch (error) {
    try {
      await reader.cancel(error);
    } catch {
      // The stream may already have observed the peer cancellation.
    }
    return { kind: 'unavailable' };
  } finally {
    reader.releaseLock();
  }

  const body = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return { body, kind: 'ok' };
};

const payloadTooLargeResponse = (path: string): Response =>
  new Response(
    JSON.stringify({
      type: 'about:blank',
      title: 'Webhook payload too large',
      status: 413,
      detail: `request body exceeds ${MERCURY_MAX_REQUEST_BODY_BYTES} bytes`,
      instance: path,
    }),
    {
      status: 413,
      headers: { 'content-type': 'application/problem+json' },
    },
  );

const problemResponse = (catalog: IntakeProblemCatalog, failure: IntakeFailure, path: string): Response => {
  const problem = catalog.fromFailure(failure, path);
  const headers = new Headers({ 'content-type': 'application/problem+json' });
  if (failure.code === 'quota-exhausted') {
    headers.set('retry-after', String(failure.retryAfterSeconds ?? 1));
  }
  return new Response(JSON.stringify(problem), {
    status: problem.status,
    headers,
  });
};

export class IntakeHttpAdapter {
  constructor(
    readonly engine: IntakeEngine,
    readonly problems: IntakeProblemCatalog,
  ) {}

  async handle(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const boundedBody = await readBoundedRequestBody(request);
    if (boundedBody.kind === 'too-large') {
      return payloadTooLargeResponse(url.pathname);
    }
    if (boundedBody.kind === 'unavailable') {
      return problemResponse(
        this.problems,
        {
          code: 'config-unavailable',
          message: 'request body could not be consumed safely',
        },
        url.pathname,
      );
    }
    const input = intakeRequestSchema.safeParse({
      path: url.pathname,
      host: request.headers.get('host') ?? url.host,
      headers: headerMap(request.headers),
      rawBody: boundedBody.body,
    });
    if (!input.success) {
      const failure: IntakeFailure = {
        code: 'unknown-route',
        message: input.error.issues.map(issue => issue.message).join('; '),
      };
      return problemResponse(this.problems, failure, url.pathname);
    }

    const domainRequest: IntakeRequest = input.data;
    const outcome = await this.engine.intake(domainRequest);
    if (await outcome.isErr()) {
      return problemResponse(this.problems, await outcome.unwrapErr(), url.pathname);
    }

    const accepted = await outcome.unwrap();
    const headers = new Headers();
    if (accepted.kind === 'accepted') {
      headers.set('x-atomi-webhook-event-id', accepted.eventId);
    }
    const response = new Response(null, { status: 200, headers });
    const acknowledged = await this.engine.acknowledgeProviderResponse(accepted.eventId);
    if (await acknowledged.isErr()) {
      return problemResponse(this.problems, await acknowledged.unwrapErr(), url.pathname);
    }
    return response;
  }
}

export const createIntakeHandler =
  (adapter: IntakeHttpAdapter): ((request: Request) => Promise<Response>) =>
  request =>
    adapter.handle(request);
