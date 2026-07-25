import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-go-lib-publish-semver-guard-green',
    description: 'The publication guard accepts an exact vX.Y.Z tag.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#ci -c ./scripts/validate/go-publish-guard.sh v1.2.3',
        'go-lib-publish-semver-guard',
      );
    },
  },
  mutation: {
    name: 'mutation-go-lib-publish-semver-guard-caught',
    description: 'A malformed release tag is refused before proxy access.',
    expectedImpact: [],
    async run(repo: any) {
      await expectRed(
        repo,
        'nix develop .#ci -c ./scripts/validate/go-publish-guard.sh release-1.2',
        'go-lib-publish-semver-guard',
      );
    },
  },
});
