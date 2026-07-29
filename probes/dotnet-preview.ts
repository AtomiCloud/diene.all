import { runWebApp } from './lib/dotnet.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-preview-green',
      description: 'The preview task executes the compiled Release artifact.',
      kind: 'baseline',
      async run(repo: any) {
        await runWebApp(repo, 'dotnet-e2e-preview', 'nix develop .#default -c pls preview');
      },
    },
  ],
};
