import { emitProblemManifest } from '@atomicloud/diene.problems';
import { serverConfig, serverLandscape } from '@/adapters/server-config';
import { buildProblemRegistry } from '@/adapters/problem-reporter/registry';

// Error-info publishing (ported from argon's pages/api/v1.0/error-info): the
// manifest of every registered Problem, addressable by the RFC 9457 type URI.
export async function GET(): Promise<Response> {
  const config = await serverConfig();
  const landscape = serverLandscape();
  return buildProblemRegistry(config.get('app'), config.get('seo'), landscape).match({
    ok: ({ registry }) => Response.json(emitProblemManifest(registry)),
    err: problem => Response.json(problem, { status: problem.status }),
  });
}
