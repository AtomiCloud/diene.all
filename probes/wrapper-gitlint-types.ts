import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-gitlint-types-green',
    description: 'Gitlint and semantic-release expose the same unified commit types.',
    async run(repo: any) {
      await expectGreen(repo, 'nix develop .#ci -c ./scripts/validate/gitlint-types.sh', 'wrapper-gitlint-types');
    },
  },
  mutation: {
    name: 'mutation-wrapper-gitlint-types-caught',
    description: 'A one-type vocabulary divergence is rejected.',
    expectedImpact: [],
    async run(repo: any) {
      await repo.patch('.gitlint', { find: ',test\n', replace: '\n' });
      await expectRed(repo, 'nix develop .#ci -c ./scripts/validate/gitlint-types.sh', 'wrapper-gitlint-types');
    },
  },
});
