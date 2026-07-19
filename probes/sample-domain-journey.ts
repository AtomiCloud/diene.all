import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-sample-domain-journey-green',
      description: 'The compiled manager runs and reports its controller/observe runtime interface.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c ./scripts/validate/sample-journey.sh', 'sample-domain-journey');
      },
    },
  ],
};
