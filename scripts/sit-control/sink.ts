import { createHmac, timingSafeEqual } from 'node:crypto';

interface Attempt {
  readonly atMs: number;
  readonly endpointId: string;
  readonly eventId: string;
  readonly landingLandscape: string;
  readonly headers: Record<string, string>;
  readonly rawBodyBase64: string;
  readonly status: number;
}

const port = Number(process.env.SIT_SINK_PORT ?? '8080');
const secretFile = process.env.SIT_ENDPOINT_SECRET_FILE;
if (!Number.isSafeInteger(port) || port < 1 || secretFile === undefined) {
  throw new Error('SIT sink requires a valid port and SIT_ENDPOINT_SECRET_FILE');
}
const secret = new Uint8Array(await Bun.file(secretFile).arrayBuffer());
if (secret.byteLength < 32) {
  throw new Error('SIT endpoint secret is too short');
}

const attempts: Attempt[] = [];
const failureBudgets = new Map<string, number>();

const verify = (header: string | null, body: Uint8Array): boolean => {
  const match = /^t=(\d+), v1=([a-f0-9]{64})$/.exec(header ?? '');
  if (match?.[1] === undefined || match[2] === undefined) return false;
  const timestamp = Number(match[1]);
  if (!Number.isSafeInteger(timestamp) || Math.abs(Date.now() / 1_000 - timestamp) > 300) return false;
  const expected = createHmac('sha256', secret).update(`${timestamp}.`).update(body).digest();
  const supplied = Buffer.from(match[2], 'hex');
  return supplied.byteLength === expected.byteLength && timingSafeEqual(supplied, expected);
};

Bun.serve({
  hostname: '0.0.0.0',
  port,
  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === '/health') return Response.json({ status: 'ready' });
    if (url.pathname === '/__control/attempts' && request.method === 'GET') {
      const endpointId = url.searchParams.get('endpointId');
      const eventId = url.searchParams.get('eventId');
      const selected = attempts.filter(
        attempt =>
          (endpointId === null || attempt.endpointId === endpointId) &&
          (eventId === null || attempt.eventId === eventId),
      );
      return Response.json({ attempts: selected, handlerInvocations: selected.length });
    }
    if (url.pathname === '/__control/failure' && request.method === 'POST') {
      const input = (await request.json()) as { endpointId?: unknown; count?: unknown };
      if (
        typeof input.endpointId !== 'string' ||
        input.endpointId.length === 0 ||
        !Number.isSafeInteger(input.count) ||
        Number(input.count) < 0
      ) {
        return Response.json({ error: 'endpointId and a non-negative integer count are required' }, { status: 400 });
      }
      failureBudgets.set(input.endpointId, Number(input.count));
      return new Response(null, { status: 204 });
    }
    if (request.method !== 'POST' || !url.pathname.startsWith('/internal/webhooks/')) {
      return Response.json({ error: 'not found' }, { status: 404 });
    }
    const body = new Uint8Array(await request.arrayBuffer());
    if (!verify(request.headers.get('x-atomi-webhook-signature'), body)) {
      return Response.json({ error: 'invalid internal signature' }, { status: 401 });
    }
    let signedPayload: {
      readonly eventId?: unknown;
      readonly landingLandscape?: unknown;
      readonly delivery?: { readonly endpointId?: unknown };
    } = {};
    try {
      signedPayload = JSON.parse(new TextDecoder().decode(body)) as typeof signedPayload;
    } catch {
      return Response.json({ error: 'invalid internal payload' }, { status: 400 });
    }
    const endpointId =
      typeof signedPayload.delivery?.endpointId === 'string'
        ? signedPayload.delivery.endpointId
        : (request.headers.get('x-atomi-webhook-endpoint-id') ?? '');
    const eventId = typeof signedPayload.eventId === 'string' ? signedPayload.eventId : '';
    const landingLandscape = typeof signedPayload.landingLandscape === 'string' ? signedPayload.landingLandscape : '';
    const failureBudget = failureBudgets.get(endpointId) ?? 0;
    const status = failureBudget > 0 ? 503 : 200;
    if (failureBudget > 0) failureBudgets.set(endpointId, failureBudget - 1);
    attempts.push({
      atMs: Date.now(),
      endpointId,
      eventId,
      landingLandscape,
      headers: Object.fromEntries(request.headers.entries()),
      rawBodyBase64: Buffer.from(body).toString('base64'),
      status,
    });
    return new Response(null, { status });
  },
});
