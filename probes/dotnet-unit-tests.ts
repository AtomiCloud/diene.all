import { expectGreen, expectRed } from './lib/helpers.ts';
import { flipAssertion } from './lib/mutations.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-unit-tests-green',
      description: 'The registered unit projects pass through the public task surface.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c task test:unit', 'dotnet-unit-tests', 600000);
      },
    },
    {
      name: 'mutation-dotnet-unit-tests-caught',
      description: 'Flipping a real FluentAssertions equality turns the unit tier red.',
      kind: 'mutation',
      expectedImpact: ['dotnet-unit-coverage', 'dotnet-multi-project-coverage'],
      async run(repo: any) {
        await flipAssertion(repo, { globs: ['UnitTest*/**/*.cs'] });
        await expectRed(repo, 'nix develop .#ci -c task test:unit', 'dotnet-unit-tests', 600000);
      },
    },
  ],
};
