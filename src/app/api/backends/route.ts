import { buildApiEngine } from '@/adapters/external/engine';
import { serverAuth } from '@/adapters/auth/server';
import { serverConfig, serverLandscape } from '@/adapters/server-config';

/**
 * Backend inventory: resolves the api-engine per request (Workers caveat 7 —
 * no cross-request client reuse) and lists the registered backend coordinates.
 * Also the SIT hook that proves the registration point composes.
 */
export async function GET(): Promise<Response> {
  const config = await serverConfig();
  const landscape = serverLandscape();
  const auth = await serverAuth(config, landscape);
  return auth
    .andThen(({ retriever }) => buildApiEngine(config, landscape, retriever))
    .match({
      ok: engine =>
        Response.json({
          landscape,
          backends: engine.list().map(backend => ({
            key: backend.key,
            coordinate: backend.coordinate,
          })),
        }),
      err: problem => Response.json(problem, { status: problem.status }),
    });
}
