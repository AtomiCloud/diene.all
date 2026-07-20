import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-bun-lib-publish-tag-policy-green',
    description: 'The CD publish path is restricted to v*.*.* tags.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#ci -c ./scripts/validate/bun-release-policy.sh trigger',
        'bun-lib-publish-tag-policy',
      );
    },
  },
  mutation: {
    name: 'mutation-bun-lib-publish-tag-policy-caught',
    description: 'Changing the publish trigger to a non-release pattern turns policy validation red.',
    expectedImpact: [],
    async run(repo: any) {
      await repo.patch('.github/workflows/cd.yaml', { find: "- 'v*.*.*'", replace: "- 'preview-*'" });
      await expectRed(
        repo,
        'nix develop .#ci -c ./scripts/validate/bun-release-policy.sh trigger',
        'bun-lib-publish-tag-policy',
      );
    },
  },
});
