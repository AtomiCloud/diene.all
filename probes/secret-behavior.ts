// COST CLASS: heavy, SERIALIZED (see probes/lib/consumer-sit.ts) — it brings the
// local dependency stack up and drives the compiled artifact.
//
// The mechanism is the two-part M33 secret contract: a value left blank in every
// committed layer is supplied by the environment per landscape, AND a blank
// ENVIRONMENT value is treated as UNSET rather than as an empty string that would
// silently override a real one.
//
// Proven-only smoke: no sabotage.
import { runSitJourney } from './lib/consumer-sit.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-secret-behavior-green',
      description: 'Blank YAML values are injected per landscape and blank environment values are treated as unset.',
      kind: 'baseline',
      async run(repo: any) {
        await runSitJourney(repo, 'TestSecretBehaviourJourney', 'secret-behavior');
      },
    },
  ],
};
