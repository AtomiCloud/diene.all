import { createHash } from 'node:crypto';

export const DEDUP_WINDOW_SECONDS = 72 * 60 * 60;

const encodeKeyPart = (value: string): string => encodeURIComponent(value);

export const deriveDedupId = (
  providerEventId: string | undefined,
  rawBody: Uint8Array,
  signatureMaterial: string,
): string => {
  if (providerEventId !== undefined && providerEventId.length > 0) {
    return `native:${Buffer.from(providerEventId, 'utf8').toString('base64url')}`;
  }

  return `sha256:${createHash('sha256').update(rawBody).update('\0').update(signatureMaterial).digest('hex')}`;
};

export const dedupKey = (tenantId: string, routeId: string, dedupId: string): string =>
  `dedup:${encodeKeyPart(tenantId)}:${encodeKeyPart(routeId)}:${encodeKeyPart(dedupId)}`;
