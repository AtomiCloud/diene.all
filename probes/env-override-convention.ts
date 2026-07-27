// COST CLASS: heavy, SERIALIZED (see probes/lib/consumer-sit.ts) — it brings the
// local dependency stack up and drives the compiled artifact.
//
// The mechanism is the R14 environment-override convention: `ATOMI_` prefix,
// `__` nesting, indexed lists. Only a real boot can prove the override actually
// WINS over the file value in the merged tree, which is why this is a SIT row and
// not a unit test of the loader.
//
// Proven-only smoke: no sabotage.
import { runSitJourney } from './lib/consumer-sit.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-env-override-convention-green',
      description: 'A SIT baseline proves an ATOMI_X__Y environment override wins over the file configuration.',
      kind: 'baseline',
      async run(repo: any) {
        await runSitJourney(repo, 'TestEnvOverrideJourney', 'env-override-convention');
      },
    },
  ],
};
