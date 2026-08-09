import { runSitJourney } from './lib/consumer-sit.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-env-override-convention-green',
      description: 'A SIT baseline proves an ATOMI_X__Y environment override wins over file configuration.',
      kind: 'baseline',
      async run(repo: any) {
        await runSitJourney(repo, 'tests/sit/env-override.sit.test.ts', 'env-override-convention');
      },
    },
  ],
};
