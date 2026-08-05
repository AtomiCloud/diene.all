import { runWithRedis } from './lib/dotnet.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-preview-green',
      description: 'The preview task executes the compiled Release artifact.',
      kind: 'baseline',
      async run(repo: any) {
        await runWithRedis(repo, 'dotnet-base-probe-preview', 'nix develop .#default -c task preview');
      },
    },
  ],
};
