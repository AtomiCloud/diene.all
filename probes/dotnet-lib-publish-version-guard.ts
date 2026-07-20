import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-lib-publish-version-guard-green',
    description: 'The publish guard accepts a tag matching the committed Version.props value.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'GITHUB_REF_NAME=v1.0.0 nix develop .#ci -c ./scripts/validate/dotnet-publish.sh',
        'dotnet-lib-publish-version-guard',
      );
    },
  },
  mutation: {
    name: 'mutation-dotnet-lib-publish-version-guard-caught',
    description: 'A tag and manifest version mismatch exits red before any publish operation.',
    expectedImpact: [],
    async run(repo: any) {
      await expectRed(
        repo,
        'GITHUB_REF_NAME=v1.0.1 nix develop .#ci -c ./scripts/validate/dotnet-publish.sh',
        'dotnet-lib-publish-version-guard',
      );
    },
  },
});
