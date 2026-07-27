import { serverConfig, serverLandscape } from '@/adapters/server-config';
import { serverAuth } from '@/adapters/auth/server';

/**
 * Auth state endpoints consumed by auth-engine's ClientAuthStateRetriever
 * (default endpoint map: tokens / claims / user / force_tokens). Each response
 * is the retriever's ResultSerial wire shape, produced by the SERVER retriever
 * over the cookie session — tokens never live in browser storage.
 */
export async function GET(_request: Request, { params }: { params: Promise<{ action: string }> }): Promise<Response> {
  const { action } = await params;
  const config = await serverConfig();
  const landscape = serverLandscape();
  const auth = await serverAuth(config, landscape);

  return auth.match({
    ok: async ({ retriever }) => {
      switch (action) {
        case 'tokens':
          return Response.json(await retriever.getTokenSet().serial());
        case 'claims':
          return Response.json(await retriever.getClaims().serial());
        case 'user':
          return Response.json(await retriever.getUserInfo().serial());
        case 'force_tokens':
          return Response.json(await retriever.forceTokenSet().serial());
        default:
          return Response.json({ title: 'Not Found', status: 404 }, { status: 404 });
      }
    },
    err: problem => Response.json(problem, { status: problem.status }),
  });
}
