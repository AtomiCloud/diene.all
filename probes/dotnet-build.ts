import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-build-green',
      description: 'The public build task produces the Release App artifact.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c task build', 'dotnet-build', 600000);
        if ((await repo.glob('App/bin/Release/net10.0/App.dll')).length !== 1) {
          throw new Error('Release App.dll was not produced');
        }
      },
    },
  ],
};
