import { buildLoginRedirect, resolveReturnTo, continueTo } from '@atomicloud/diene.auth-engine';
import { cookies } from 'next/headers';
import { serverConfig, serverLandscape } from '@/lib/server-config';
import { serverAuth } from '@/adapters/auth/server';
import { codeChallengeS256, randomToken } from '@/adapters/auth/pkce';

const PKCE_COOKIE = 'diene.auth.pkce';
const STATE_COOKIE = 'diene.auth.state';
const RETURN_COOKIE = 'diene.auth.return';

export { buildLoginRedirect };

/**
 * OIDC front-channel routes (ported from argon's pages/api/logto/[action]):
 * sign-in starts the PKCE authorization-code flow, callback exchanges the
 * code into the cookie session, sign-out clears it. returnTo survives the
 * whole journey (login redirect-return gate: path AND query preserved).
 */
export async function GET(request: Request, { params }: { params: Promise<{ action: string }> }): Promise<Response> {
  const { action } = await params;
  const config = await serverConfig();
  const landscape = serverLandscape();
  const seoBase = config.get('seo').baseUrl;
  const url = new URL(request.url);
  const jar = await cookies();
  const secure = seoBase.startsWith('https:');
  const cookieOptions = { httpOnly: true, sameSite: 'lax' as const, secure, path: '/', maxAge: 600 };

  const auth = await serverAuth(config, landscape);
  return auth.match({
    ok: async ({ provider, problems }) => {
      switch (action) {
        case 'sign-in': {
          const returnTo = await resolveReturnTo(url.searchParams.get('returnTo') ?? '/', {
            InvalidReturnTo: problems.InvalidReturnTo,
          }).unwrapOr('/');
          const verifier = randomToken();
          const state = randomToken();
          jar.set(PKCE_COOKIE, verifier, cookieOptions);
          jar.set(STATE_COOKIE, state, cookieOptions);
          jar.set(RETURN_COOKIE, returnTo, cookieOptions);
          const signIn = await provider
            .signInUrl({
              redirectUri: new URL('/api/logto/callback', seoBase).toString(),
              state,
              codeChallenge: await codeChallengeS256(verifier),
            })
            .serial();
          return signIn[0] === 'ok'
            ? Response.redirect(signIn[1], 302)
            : Response.json(signIn[1], { status: signIn[1].status });
        }
        case 'callback': {
          const state = url.searchParams.get('state') ?? '';
          const code = url.searchParams.get('code') ?? '';
          const expectedState = jar.get(STATE_COOKIE)?.value ?? '';
          const verifier = jar.get(PKCE_COOKIE)?.value ?? '';
          if (state === '' || state !== expectedState || code === '' || verifier === '') {
            return Response.json({ title: 'Invalid login state', status: 400 }, { status: 400 });
          }
          const exchanged = await provider
            .exchangeAuthorizationCode({
              code,
              redirectUri: new URL('/api/logto/callback', seoBase).toString(),
              codeVerifier: verifier,
            })
            .serial();
          jar.delete(PKCE_COOKIE);
          jar.delete(STATE_COOKIE);
          if (exchanged[0] === 'err') {
            return Response.json(exchanged[1], { status: exchanged[1].status });
          }
          const returnTo = continueTo(jar.get(RETURN_COOKIE)?.value ?? '/');
          jar.delete(RETURN_COOKIE);
          return Response.redirect(new URL(returnTo, seoBase), 302);
        }
        case 'sign-out': {
          await provider.clearTokens().serial();
          return Response.redirect(new URL('/', seoBase), 302);
        }
        default:
          return Response.json({ title: 'Not Found', status: 404 }, { status: 404 });
      }
    },
    err: problem => Response.json(problem, { status: problem.status }),
  });
}
