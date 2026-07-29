import { runWebApp } from './lib/dotnet.ts';
import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-dev-green',
      description: 'The hot-reload development task starts the sample App.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#default -c dotnet build App/App.csproj -c Debug -m:1 /nodeReuse:false /p:UseSharedCompilation=false',
          'dotnet-dev-build',
          480000,
        );
        await runWebApp(repo, 'dotnet-e2e-dev', 'nix develop .#default -c pls dev');
      },
    },
  ],
};
