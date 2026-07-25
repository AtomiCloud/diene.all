import { expectGreen, expectRed } from './lib/helpers.ts';
import { flipGoAssertion } from './lib/go.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-unit-tests-green',
      description: 'Black-box unit tests pass against the public domain surface.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c ./scripts/local/test.sh unit false false', 'unit-tests');
      },
    },
    {
      name: 'mutation-unit-tests-caught',
      description: 'Flipping one public-surface assertion must turn the unit tier red.',
      kind: 'mutation',
      async run(repo: any) {
        await flipGoAssertion(repo);
        await expectRed(repo, 'nix develop .#ci -c ./scripts/local/test.sh unit false false', 'unit-tests');
      },
    },
  ],
};
