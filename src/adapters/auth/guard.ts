import 'server-only';

import { buildLoginRedirect, checkHomeLandscape } from '@atomicloud/diene.auth-engine';
import { redirect } from 'next/navigation';
import { serverConfig, serverLandscape } from '@/adapters/server-config';
import { serverAuth } from '@/adapters/auth/server';

export interface GuardedSession {
  readonly claims: Readonly<Record<string, unknown>>;
  /** 'home' when the home claim is present; 'pre-onboarding' sends to the picker. */
  readonly home: { readonly phase: 'home'; readonly landscape: string } | { readonly phase: 'pre-onboarding' };
}

/**
 * SSR auth-redirect guard: an unauthenticated request to a protected page
 * redirects to login CARRYING returnTo (path + query — the redirect-return
 * gate's journey), and every sign-in checks the home claim (present → home,
 * absent → picker; ARCHITECTURE §5).
 */
export const requireSession = async (returnTo: string): Promise<GuardedSession> => {
  const config = await serverConfig();
  const landscape = serverLandscape();
  const auth = await serverAuth(config, landscape);

  const session = await auth.andThen(({ retriever }) => retriever.getClaims()).serial();

  if (session[0] === 'err' || session[1].__kind === 'unauthed') {
    redirect(buildLoginRedirect('/api/logto/sign-in', returnTo));
  }

  const claims = session[1].value.data as Readonly<Record<string, unknown>>;
  const home = await checkHomeLandscape(claims).unwrapOr({ phase: 'pre-onboarding' } as const);
  return { claims, home };
};
