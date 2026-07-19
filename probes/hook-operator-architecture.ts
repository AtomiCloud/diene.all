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
      description: 'Importing a k8s package into lib/operator must redden the boundary hook.',
      kind: 'mutation',
      async run(repo: any) {
        await repo.patch('lib/operator/brake/brake.go', {
          find: 'import "fmt"',
          replace: 'import (\n\t"fmt"\n\n\t_ "k8s.io/apimachinery/pkg/runtime"\n)',
        });
        await expectRed(repo, cmd, 'hook-operator-architecture');
      },
    },
  ],
};
