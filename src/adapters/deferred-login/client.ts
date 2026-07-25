'use client';

import { buildIosClipboardPayload, initiateHandoff, type InitiateHandoffResult } from '@atomicloud/diene.auth-engine';
import type { Problem } from '@atomicloud/diene.problems';
import type { Result } from '@atomicloud/diene.result';
import type { AuthProblems } from '@atomicloud/diene.auth-engine';

export { buildIosClipboardPayload };

/**
 * Deferred-login CLIENT module: dotnet-api hosts the mint/redeem endpoints —
 * this client only INITIATES the handoff against its `/app-handoff` mount and
 * builds store carriers (Android install referrer, iOS clipboard page).
 * Server-side enforcement (dotnet-api): nonce TTL = 15 minutes, one-time
 * redeem token expiresIn = 120 s.
 */
export const initiateDeferredLogin = (options: {
  readonly dotnetApiBaseUrl: string;
  readonly mount: string;
  readonly accessToken: string;
  readonly problems: Pick<AuthProblems, 'AppHandoffExpired' | 'AuthRefreshFailed' | 'Unauthorized'>;
}): Result<InitiateHandoffResult, Problem> =>
  initiateHandoff({
    fetch: (input, init) => fetch(input, init),
    baseUrl: options.dotnetApiBaseUrl,
    mount: options.mount,
    accessToken: options.accessToken,
    problems: options.problems,
  });
