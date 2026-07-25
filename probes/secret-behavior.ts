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
        await runSitJourney(repo, 'tests/sit/secret-behavior.sit.test.ts', 'secret-behavior');
      },
    },
  ],
};
