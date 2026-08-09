import { runSitJourney } from './lib/consumer-sit.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-health-metric-green',
      description: 'The expected OTEL health-check metric is observed in the local metrics backend.',
      kind: 'baseline',
      async run(repo: any) {
        await runSitJourney(repo, 'tests/sit/otel-export.sit.test.ts', 'health-metric');
      },
    },
  ],
};
