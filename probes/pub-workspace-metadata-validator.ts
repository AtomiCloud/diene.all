import { expectGreen, expectRed } from './lib/helpers.ts';

// Gate: `scripts/validate/dart-package.sh` asserts the pub-workspace metadata
// contract (member resolution, root workspace listing, publishable identity,
// required artifacts). Sabotage breaks the member's `resolution: workspace`
// declaration and proves the validator rejects it.
export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-pub-workspace-metadata-validator-green',
      description: 'the package metadata validator passes on the pristine template',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#ci --no-write-lock-file -c ./scripts/validate/dart-package.sh',
          'pub-workspace-metadata-validator',
        );
      },
    },
    {
      name: 'mutation-pub-workspace-metadata-validator-caught',
      description: 'the validator fails when the member drops resolution: workspace',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.patch('packages/diene_problems/pubspec.yaml', {
          find: 'resolution: workspace',
          replace: 'resolution: none',
        });
        await expectRed(
          repo,
          'nix develop .#ci --no-write-lock-file -c ./scripts/validate/dart-package.sh',
          'pub-workspace-metadata-validator',
        );
      },
    },
  ],
};
