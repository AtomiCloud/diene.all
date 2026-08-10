import { expectGreen, expectRed } from './lib/helpers.ts';

// Freshly generate the CRDs into a temp dir and validate the invalid fixture
// against THOSE schemas, so a removed validation marker actually reddens (the
// committed CRD is never trusted for this gate).
const cmd =
  'nix develop .#ci -c bash -lc \'d=$(mktemp -d); controller-gen crd paths=./api/... output:crd:dir="$d"; CRD_DIR="$d" go test -count=1 -run TestInvalidNoteRejectedBySchema ./tests/int/operator/\'';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-operator-crd-schema-validation-green',
      description: 'A freshly generated OpenAPI schema rejects the invalid Note fixture (envtest).',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, cmd, 'operator-crd-schema-validation');
      },
    },
    {
      name: 'mutation-operator-crd-schema-validation-caught',
      description: 'Removing a required validation marker must admit the formerly-invalid fixture (red).',
      kind: 'mutation',
      async run(repo: any) {
        await repo.patch('api/v1alpha1/note_types.go', {
          find: '// +kubebuilder:validation:Enum=personal;work;archive',
          replace: '// (enum marker removed)',
        });
        await expectRed(repo, cmd, 'operator-crd-schema-validation');
      },
    },
  ],
};
