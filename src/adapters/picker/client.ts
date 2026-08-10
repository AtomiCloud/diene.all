'use client';

import {
  handoffToAuthEngine,
  parseDocB,
  pickHome,
  pingLandscapes,
  validateEndpoint,
  type AuthEngineHandoff,
  type DocB,
  type PingResult,
  type Transport,
} from '@atomicloud/diene.frontend-utils/discovery';
import type { PickerConfig } from '@/config';
import { pickerAllowlist, pickerPingRoot } from '@/lib/allowlist';

export type { PingResult, AuthEngineHandoff };

const browserTransport: Transport = {
  fetch: async url => {
    try {
      const response = await fetch(url, { signal: AbortSignal.timeout(5000) });
      const body = await response.text();
      return response.ok
        ? { kind: 'ok', status: response.status, body }
        : { kind: 'http-error', status: response.status };
    } catch (error) {
      return error instanceof DOMException && error.name === 'TimeoutError'
        ? { kind: 'timeout' }
        : { kind: 'connect-failure' };
    }
  },
};

/**
 * Fetch Doc B (landscape selector — names+metadata ONLY, SIGN-UP ONLY). The
 * doc URL and every derived ping URL validate against the BAKED endpoint
 * suffix allowlist at use time; the auth issuer is always baked and never
 * doc-sourced.
 */
export const fetchDocB = async (picker: PickerConfig): Promise<DocB> => {
  const validated = validateEndpoint(picker.docBUrl, pickerAllowlist(picker));
  const url = await validated.match({
    ok: parsed => parsed.toString(),
    err: error => {
      throw new Error(`Doc B URL rejected by allowlist: ${JSON.stringify(error)}`);
    },
  });
  const outcome = await browserTransport.fetch(url);
  if (outcome.kind !== 'ok') throw new Error(`Doc B fetch failed: ${outcome.kind}`);
  return parseDocB(JSON.parse(outcome.body)).match({
    ok: doc => doc,
    err: error => {
      throw new Error(`Doc B malformed: ${JSON.stringify(error)}`);
    },
  });
};

/** Ping every Doc B landscape at its convention-derived URL (ping-and-pick). */
export const pingAll = async (doc: DocB, picker: PickerConfig): Promise<readonly PingResult[]> => {
  const root = pickerPingRoot(picker);
  return pingLandscapes(doc, { root }, browserTransport, { now: () => performance.now() }, pickerAllowlist(picker));
};

/** The user's confirmed pick → the auth-engine handoff boundary object. */
export const confirmHome = (pings: readonly PingResult[], chosen: string): Promise<AuthEngineHandoff> =>
  pickHome(pings, chosen).match({
    ok: assignment => handoffToAuthEngine(assignment),
    err: error => {
      throw new Error(`home pick failed: ${JSON.stringify(error)}`);
    },
  });
