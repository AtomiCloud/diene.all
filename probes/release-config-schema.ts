import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-release-config-schema-green',
      description: 'The release configuration parses and satisfies the workspace schema.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#ci -c ./scripts/validate/release-config.sh schema',
          'release-config-schema',
        );
      },
    },
    {
      name: 'mutation-release-config-schema-caught',
      description: 'A focused sabotage must turn the release-config-schema mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // The anchor is indented four spaces, not two: the workspace cascade
        // (c8f5877 route, schemaVersion 2) nested `branches:` one level deeper
        // under its parent key. The old two-space anchor stopped matching and
        // `repo.patch` correctly hard-failed rather than sabotaging nothing —
        // which is the right behaviour, and is why this surfaced as `invalid`
        // (sandbox_operation_failed) instead of a silently vacuous `caught`.
        await repo.patch('atomi_release.yaml', {
          find: 'branches:\n    - main',
          replace: 'branches:\n    - develop',
        });
        await expectRed(
          repo,
          'nix develop .#ci -c ./scripts/validate/release-config.sh schema',
          'release-config-schema',
        );
      },
    },
  ],
};
