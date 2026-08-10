import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-bun-lib-publish-version-guard-green',
    description: 'The publish guard accepts the tag matching the committed manifest version.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'GITHUB_REF_NAME=v1.3.1 nix develop .#ci -c ./scripts/validate/bun-publish-version.sh',
        'bun-lib-publish-version-guard',
      );
    },
  },
  mutation: {
    name: 'mutation-bun-lib-publish-version-guard-caught',
    description: 'A manifest and tag mismatch exits red before publication.',
    expectedImpact: [],
    async run(repo: any) {
      await expectRed(
        repo,
        'GITHUB_REF_NAME=v1.3.2 nix develop .#ci -c ./scripts/validate/bun-publish-version.sh',
        'bun-lib-publish-version-guard',
      );
    },
  },
});
