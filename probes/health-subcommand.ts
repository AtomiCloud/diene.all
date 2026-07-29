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
        await runSitJourney(repo, 'tests/sit/health.sit.test.ts', 'health-subcommand');
      },
    },
  ],
};
