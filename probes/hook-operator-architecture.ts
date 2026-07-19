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
      description: 'Moving a domain decision (a brake dependency) into a controller must redden the hook.',
      kind: 'mutation',
      async run(repo: any) {
        await repo.patch('adapters/operator/controllers/note_controller.go', {
          find: '"github.com/AtomiCloud/diene.go-base/lib/operator/reconcile"',
          replace:
            '"github.com/AtomiCloud/diene.go-base/lib/operator/brake"\n\t"github.com/AtomiCloud/diene.go-base/lib/operator/reconcile"',
        });
        await expectRed(repo, cmd, 'hook-operator-architecture');
      },
    },
  ],
};
