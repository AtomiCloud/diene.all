import 'server-only';

import {
  createLogtoAuthProvider,
  decodeToken,
  registerAuthProblems,
  systemClock,
  ServerAuthStateRetriever,
  type AuthProblems,
  type CanonicalResourceKey,
  type LogtoAuthProvider,
} from '@atomicloud/diene.auth-engine';
import type { Problem } from '@atomicloud/diene.problems';
import type { Result } from '@atomicloud/diene.result';
import { cookies } from 'next/headers';
import type { RootConfig } from '@/lib/server-config';
import { buildProblemRegistry } from '@/adapters/problem-reporter/registry';
import { cookieTokenStorage, hasSessionCookie } from './session';

export interface ServerAuth {
  readonly provider: LogtoAuthProvider;
  readonly problems: AuthProblems;
  readonly retriever: ServerAuthStateRetriever;
}

/** Per-backend resource audiences derived from the config registration point. */
const resourceAudiences = (config: RootConfig, landscape: string): Record<CanonicalResourceKey, string> =>
  Object.fromEntries(
    Object.entries(config.get('backends')).map(([name, backend]) => [
      `${backend.platform}/${landscape}/${backend.service}/${name}`,
      backend.baseUrl,
    ]),
  );

/**
 * Per-request server auth assembly (Workers caveat 7 — never cached across
 * requests): logto provider over the cookie session store, with the app's
 * Problem registry supplying the typed auth failures. All endpoints and
 * client-ids come from config (R21) — nothing identity-bearing is hardcoded.
 */
export const serverAuth = async (config: RootConfig, landscape: string): Promise<Result<ServerAuth, Problem>> => {
  const jar = await cookies();
  const auth = config.get('auth');
  const secure = config.get('seo').baseUrl.startsWith('https:');
  return buildProblemRegistry(config.get('app'), config.get('seo'), landscape).andThen(({ registry }) =>
    registerAuthProblems(registry).andThen(problems =>
      createLogtoAuthProvider({
        endpoint: auth.logto.endpoint,
        appId: auth.logto.appId,
        appSecret: auth.logto.appSecret,
        storage: cookieTokenStorage(jar, secure),
        problems,
        clock: systemClock,
      }).map(provider => ({
        provider,
        problems,
        retriever: new ServerAuthStateRetriever({
          provider,
          resources: resourceAudiences(config, landscape),
          session: {
            isAuthenticated: () => hasSessionCookie(jar),
            getUserInfo: () => provider.getIdToken().andThen(idToken => decodeToken(idToken)),
          },
        }),
      })),
    ),
  );
};
