import { createHmac, timingSafeEqual } from 'node:crypto';
import type { DeliveryJob, WebhookEnvelope } from './models.ts';

export const DELIVERY_ENVELOPE_MEDIA_TYPE = 'application/vnd.atomi.webhook.v1+json';

export interface CanonicalDeliveryEnvelopeInput {
  readonly attempt: number;
  readonly event: WebhookEnvelope;
  readonly job: Pick<DeliveryJob, 'endpointId' | 'eventId' | 'routeId' | 'tenantId'>;
  readonly replay: boolean;
}

const canonicalProviderHeaders = (headers: WebhookEnvelope['headers']): Readonly<Record<string, readonly string[]>> => {
  const canonical: Record<string, string[]> = {};
  const normalized = Object.entries(headers).map(([name, value]) => [name.toLowerCase(), value] as const);
  normalized.sort(([left], [right]) => (left < right ? -1 : left > right ? 1 : 0));
  for (const [name, value] of normalized) {
    const values = canonical[name] ?? [];
    values.push(value);
    canonical[name] = values;
  }
  return canonical;
};

/**
 * Serializes the authoritative v1 consumer envelope in one deterministic field
 * order. The exact returned bytes are both sent and MACed, so identity cannot
 * be detached from payload or rewritten through unsigned HTTP headers.
 */
export const serializeCanonicalDeliveryEnvelope = (input: CanonicalDeliveryEnvelopeInput): Uint8Array => {
  if (!Number.isSafeInteger(input.attempt) || input.attempt < 1) {
    throw new RangeError('delivery envelope attempt must be a positive integer');
  }
  if (
    input.event.id !== input.job.eventId ||
    input.event.tenantId !== input.job.tenantId ||
    input.event.routeId !== input.job.routeId
  ) {
    throw new TypeError('delivery job identity does not match its persisted event');
  }

  const contentType = input.event.headers['content-type'] ?? 'application/octet-stream';
  return new TextEncoder().encode(
    JSON.stringify({
      version: 1,
      eventId: input.event.id,
      dedupId: input.event.dedupId,
      tenantId: input.event.tenantId,
      routeId: input.event.routeId,
      provider: input.event.provider,
      landingLandscape: input.event.landingLandscape,
      receivedAt: new Date(input.event.receivedAtMs).toISOString(),
      providerEventId: input.event.providerEventId ?? null,
      providerTimestamp:
        input.event.providerTimestampMs === undefined ? null : new Date(input.event.providerTimestampMs).toISOString(),
      providerSequence: input.event.providerSequence ?? null,
      providerHeaders: canonicalProviderHeaders(input.event.headers),
      payload: {
        contentType,
        bodyBase64: Buffer.from(input.event.rawBody).toString('base64'),
      },
      delivery: {
        endpointId: input.job.endpointId,
        attempt: input.attempt,
        replay: input.replay,
      },
    }),
  );
};

const signaturePayload = (timestampSeconds: number, rawBody: Uint8Array): Uint8Array => {
  const prefix = new TextEncoder().encode(`${timestampSeconds}.`);
  const payload = new Uint8Array(prefix.byteLength + rawBody.byteLength);
  payload.set(prefix, 0);
  payload.set(rawBody, prefix.byteLength);
  return payload;
};

export interface InternalSignature {
  readonly header: string;
  readonly timestampSeconds: number;
}

export class InternalDeliverySigner {
  sign(rawBody: Uint8Array, secret: Uint8Array, timestampSeconds: number): InternalSignature {
    const digest = createHmac('sha256', secret).update(signaturePayload(timestampSeconds, rawBody)).digest('hex');
    return { header: `t=${timestampSeconds}, v1=${digest}`, timestampSeconds };
  }

  verify(
    header: string,
    rawBody: Uint8Array,
    secret: Uint8Array,
    nowSeconds: number,
    toleranceSeconds = 5 * 60,
  ): boolean {
    const parameters = header.split(',');
    if (parameters.length !== 2) {
      return false;
    }

    let timestampText: string | undefined;
    let supplied: string | undefined;
    for (const parameter of parameters) {
      const match = /^[\t ]*([a-z0-9]+)[\t ]*=[\t ]*([^\t ]+)[\t ]*$/.exec(parameter);
      if (match === null) {
        return false;
      }
      if (match[1] === 't' && timestampText === undefined) {
        timestampText = match[2];
      } else if (match[1] === 'v1' && supplied === undefined) {
        supplied = match[2];
      } else {
        return false;
      }
    }
    if (timestampText === undefined || supplied === undefined || !/^\d+$/.test(timestampText)) {
      return false;
    }
    if (!/^[a-f0-9]{64}$/.test(supplied)) {
      return false;
    }

    const timestamp = Number(timestampText);
    if (!Number.isSafeInteger(timestamp) || Math.abs(nowSeconds - timestamp) > toleranceSeconds) {
      return false;
    }

    const expected = createHmac('sha256', secret).update(signaturePayload(timestamp, rawBody)).digest('hex');
    const suppliedBytes = Buffer.from(supplied, 'hex');
    const expectedBytes = Buffer.from(expected, 'hex');
    return suppliedBytes.byteLength === expectedBytes.byteLength && timingSafeEqual(suppliedBytes, expectedBytes);
  }
}
