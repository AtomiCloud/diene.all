import { emitProblemManifest } from '@atomicloud/diene.problems';
import { serverConfig, serverLandscape } from '@/lib/server-config';
import { buildProblemRegistry } from '@/adapters/problem-reporter/registry';

// Per-problem error-info document: the target of each Problem's `type` URI.
export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }): Promise<Response> {
  const { id } = await params;
  const config = await serverConfig();
  const landscape = serverLandscape();
  return buildProblemRegistry(config.get('app'), config.get('seo'), landscape).match({
    ok: ({ registry }) => {
      const entry = emitProblemManifest(registry).problems.find(problem => problem.id === id);
      return entry === undefined
        ? Response.json({ title: 'Not Found', status: 404 }, { status: 404 })
        : Response.json(entry);
    },
    err: problem => Response.json(problem, { status: problem.status }),
  });
}
