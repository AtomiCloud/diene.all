import { addSecondUnitProject } from './lib/dotnet.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-multi-project-coverage-green',
      description: 'A registered Lib2 and UnitTest2 automatically join the merged unit ledger.',
      kind: 'baseline',
      async run(repo: any) {
        const solution = await repo.read('dotnet-base.slnx');
        const testConfig = await repo.read('.config/dotnet-base.test.yaml');
        try {
          await addSecondUnitProject(repo, false);
          await expectGreen(
            repo,
            'nix develop .#ci -c task test:unit:coverage',
            'dotnet-multi-project-coverage',
            600000,
          );
        } finally {
          await repo.write('dotnet-base.slnx', solution);
          await repo.write('.config/dotnet-base.test.yaml', testConfig);
          await repo.exec('rm -rf Lib2 UnitTest2');
        }
      },
    },
    {
      name: 'mutation-dotnet-multi-project-coverage-caught',
      description: 'An uncovered Lib2 member is caught without filter, Codecov, or CI surgery.',
      kind: 'mutation',
      expectedImpact: [
        'dotnet-coverage-artifact-scope',
        'dotnet-unit-coverage',
        'dotnet-deadcode-all',
        'dotnet-deadcode-production',
      ],
      async run(repo: any) {
        await addSecondUnitProject(repo, true);
        await expectRed(repo, 'nix develop .#ci -c task test:unit:coverage', 'dotnet-multi-project-coverage', 600000);
      },
    },
  ],
};
