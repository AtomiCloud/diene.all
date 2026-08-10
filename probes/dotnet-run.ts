import { runWithRedis } from './lib/dotnet.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-run-green',
      description: 'The development run task executes the sample App.',
      kind: 'baseline',
      async run(repo: any) {
        await runWithRedis(repo, 'dotnet-base-probe-run', 'nix develop .#default -c task run');
      },
    },
  ],
};
