import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-integration-tests-green',
      description: 'The source-owned versioned C0 fixture round-trips through the shipped codecs.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c pls test:int', 'dotnet-integration-tests', 600000);
      },
    },
    {
      name: 'mutation-dotnet-integration-tests-caught',
      description: 'Changing the source-owned C0 Ok payload turns the integration tier red.',
      kind: 'mutation',
      expectedImpact: ['dotnet-integration-coverage'],
      async run(repo: any) {
        await repo.patch('fixtures/c0/monad-v1.json', {
          find: '    "ok": ["ok", 42],',
          replace: '    "ok": ["ok", 43],',
        });
        await expectRed(repo, 'nix develop .#ci -c pls test:int', 'dotnet-integration-tests', 600000);
      },
    },
  ],
};
