import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'presence-codecov-config',
      description: 'Informational unit and integration flags exist with carryforward enabled.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          "nix develop .#ci -c yq -e '.flags.unit.carryforward == true and .flags.int.carryforward == true' .codecov.yaml",
          'codecov-config',
        );
      },
    },
  ],
};
