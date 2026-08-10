import { expectGreen, expectRed } from './lib/helpers.ts';

const cmd = 'nix develop .#ci -c pre-commit run a-operator-architecture --all-files';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-hook-operator-architecture-green',
      description: 'The architecture hook passes with a k8s-free pure domain layer.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, cmd, 'hook-operator-architecture');
      },
    },
    {
      name: 'mutation-hook-operator-architecture-caught',
      description:
        'Inlining a real business decision into a controller (a magnitude comparison using only k8s APIs, no new import) must redden the AST boundary hook.',
      kind: 'mutation',
      async run(repo: any) {
        await repo.patch('adapters/operator/controllers/note_controller.go', {
          find: 'desiredNames := reconcile.DesiredNames(note.Name, spec)',
          replace:
            'if note.Spec.Replicas > 3 {\n\t\tnote.Spec.Replicas = 3\n\t}\n\tdesiredNames := reconcile.DesiredNames(note.Name, spec)',
        });
        await expectRed(repo, cmd, 'hook-operator-architecture');
      },
    },
  ],
};
