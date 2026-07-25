import { buildIosClipboardPayload, initiateHandoff } from '@atomicloud/diene.auth-engine';
import { serverConfig, serverLandscape } from '@/adapters/server-config';
import { serverAuth } from '@/adapters/auth/server';

/**
 * Deferred-login initiation (CLIENT half of the handoff — dotnet-api hosts the
 * mint/redeem endpoints): the authenticated web session initiates against
 * dotnet-api's /app-handoff mount and receives carriers to hand to the app
 * stores. Nonce TTL = 15 min and the 120 s one-time redeem token are enforced
 * server-side by dotnet-api.
 */
export async function POST(): Promise<Response> {
  const config = await serverConfig();
  const landscape = serverLandscape();
  const backend = config.get('backends')['dotnet-api'];
  if (backend === undefined) {
    return Response.json({ title: 'dotnet-api backend not configured', status: 501 }, { status: 501 });
  }

  const auth = await serverAuth(config, landscape);
  return auth.match({
    ok: async ({ retriever, problems }) => {
      const tokens = await retriever.getTokenSet().serial();
      if (tokens[0] === 'err' || tokens[1].__kind === 'unauthed') {
        return Response.json({ title: 'Unauthorized', status: 401 }, { status: 401 });
      }
      const accessToken = Object.values(tokens[1].value.data.accessTokens)[0] ?? '';
      const initiated = await initiateHandoff({
        fetch: (input, init) => fetch(input, init),
        baseUrl: backend.baseUrl,
        mount: config.get('auth').handoff.mount,
        accessToken,
        problems,
      }).serial();
      if (initiated[0] === 'err') {
        return Response.json(initiated[1], { status: initiated[1].status });
      }
      return Response.json({
        nonce: initiated[1].nonce,
        expiresAt: initiated[1].expiresAt.toString(),
        iosClipboardPayload: buildIosClipboardPayload(initiated[1].nonce),
      });
    },
    err: problem => Response.json(problem, { status: problem.status }),
  });
}
