import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-integration-tests-green',
      description: 'The Redis adapter passes against a real Testcontainers dependency.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c task test:int', 'dotnet-integration-tests', 600000);
      },
    },
    {
      name: 'mutation-dotnet-integration-tests-caught',
      description: 'Breaking the adapter read path turns the integration tier red.',
      kind: 'mutation',
      expectedImpact: [
        'dotnet-integration-coverage',
        'dotnet-deadcode-all',
        'dotnet-deadcode-production',
        'dotnet-dev',
        'dotnet-run',
        'dotnet-preview',
      ],
      async run(repo: any) {
        let mutated = false;
        for (const path of (await repo.glob('App*/Adapters/**/*.cs')).sort()) {
          const source = await repo.read(path);
          if (!/\breturn\s+[^;\n]+;/.test(source)) continue;
          await repo.write(
            path,
            source.replace(/\breturn\s+[^;\n]+;/, 'throw new System.InvalidOperationException("probe");'),
          );
          mutated = true;
          break;
        }
        if (!mutated) throw new Error('no adapter return statement found for the integration-test sabotage');
        await expectRed(repo, 'nix develop .#ci -c task test:int', 'dotnet-integration-tests', 600000);
      },
    },
  ],
};
