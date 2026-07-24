import { expectGreen, expectRed } from './lib/helpers.ts';

const cmd = 'nix develop .#ci -c pre-commit run a-operator-markers --all-files';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-hook-operator-marker-lint-green',
      description:
        'The marker-lint hook passes with the required kubebuilder markers present at every declared kind, spec field, and controller.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, cmd, 'hook-operator-marker-lint');
      },
    },
    {
      name: 'mutation-hook-operator-marker-lint-caught',
      description:
        'Dropping one required print column from a root kind, while its other print columns and every other marker family stay intact, must redden the hook.',
      kind: 'mutation',
      async run(repo: any) {
        await repo.patch('api/v1alpha1/note_types.go', {
          find: '+kubebuilder:printcolumn:name="Copies"',
          replace: '(required print column removed)',
        });
        await expectRed(repo, cmd, 'hook-operator-marker-lint');
      },
    },
  ],
};
