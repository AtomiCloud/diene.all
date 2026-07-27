// COST CLASS: heavy, SERIALIZED (see probes/lib/consumer-sit.ts) — it brings the
// local dependency stack up and drives the compiled artifact.
//
// The mechanism is `<bin> health` reporting worker heartbeat and internal state
// and NEVER dialling a dependency (R20/DQ16). The charts' liveness and readiness
// exec probes are runtime behavior proven by app-chart-template and
// app-chart-install; dependency reachability belongs to the db-init journey.
//
// Proven-only smoke: no sabotage.
import { runSitJourney } from './lib/consumer-sit.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-health-subcommand-green',
      description: 'The compiled binary answers the dependency-blind health subcommand journey.',
      kind: 'baseline',
      async run(repo: any) {
        await runSitJourney(repo, 'TestHealthJourney', 'health-subcommand');
      },
    },
  ],
};
