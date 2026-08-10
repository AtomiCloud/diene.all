import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-sample-domain-journey-green',
      description:
        'The source and preview tasks target the manager, then an envtest-started manager independently converges Note and Journal.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c ./scripts/validate/sample-journey.sh', 'sample-domain-journey');
      },
    },
  ],
};
