import { expectGreen, expectRed } from './lib/helpers.ts';

const cmd = 'nix develop .#ci -c pre-commit run a-operator-crd-drift --all-files';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-hook-operator-crd-drift-green',
      description: 'The CRD-drift hook passes: committed CRDs equal the regenerated output.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, cmd, 'hook-operator-crd-drift');
      },
    },
    {
      name: 'mutation-hook-operator-crd-drift-caught',
      description: 'Editing an API type without regenerating must redden the drift hook.',
      kind: 'mutation',
      async run(repo: any) {
        await repo.patch('api/v1alpha1/note_types.go', {
          find: '// +kubebuilder:validation:Enum=personal;work;archive',
          replace: '// +kubebuilder:validation:Enum=personal;work;archive;extra',
        });
        await expectRed(repo, cmd, 'hook-operator-crd-drift');
      },
    },
  ],
};
