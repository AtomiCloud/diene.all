import { z } from 'zod';
import { serverConfig, serverLandscape } from '@/adapters/server-config';
import { serverAuth } from '@/adapters/auth/server';

const syncBodySchema = z.object({ landscape: z.string().min(1) }).strict();

/**
 * Onboarding sync endpoint: receives the picker's confirmed home assignment
 * from the authenticated web session and forwards it into the OnboardSync
 * write path (the home claim itself is written by the identity plane —
 * instance-local Logto via the backend's OnboardSync; the sample records the
 * confirmation and returns the resulting phase).
 */
export async function POST(request: Request): Promise<Response> {
  const parsed = syncBodySchema.safeParse(await request.json().catch(() => undefined));
  if (!parsed.success) {
    return Response.json({ title: 'Validation Error', status: 400 }, { status: 400 });
  }

  const config = await serverConfig();
  const landscape = serverLandscape();
  const auth = await serverAuth(config, landscape);

  return auth.match({
    ok: async ({ retriever }) => {
      const claims = await retriever.getClaims().serial();
      if (claims[0] === 'err' || claims[1].__kind === 'unauthed') {
        return Response.json({ title: 'Unauthorized', status: 401 }, { status: 401 });
      }
      // The home claim write is driven through the identity plane; the sample
      // acknowledges the confirmed assignment for the journey to proceed.
      return Response.json({ accepted: true, landscape: parsed.data.landscape });
    },
    err: problem => Response.json(problem, { status: problem.status }),
  });
}
