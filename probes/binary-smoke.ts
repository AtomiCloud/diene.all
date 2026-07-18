import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-binary-smoke-green',
      description: 'Every declared repository binary answers a real smoke invocation.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#default -c ./scripts/validate/binary-smoke.sh', 'binary-smoke');
      },
    },
  ],
};
