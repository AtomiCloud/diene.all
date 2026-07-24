import { expectGreen } from './lib/helpers.ts';

// Presence: codecov.yml declares the informational unit and meta flags with
// carryforward and non-blocking project/patch statuses, matching the two-tier
// coverage model.
export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-codecov-configuration-present',
      description: 'codecov.yml declares carryforward unit/meta flags and informational statuses',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          "nix develop .#ci --no-write-lock-file -c yq -e '.flags.unit.carryforward == true and .flags.meta.carryforward == true and .coverage.status.project.default.informational == true and .coverage.status.patch.default.informational == true' codecov.yml",
          'codecov-configuration',
        );
      },
    },
  ],
};
