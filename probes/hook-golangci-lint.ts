import { expectGreen, expectRed } from './lib/helpers.ts';
import { plantGoFile } from './lib/go.ts';

const gate = 'nix develop .#ci -c pre-commit run a-golangci-lint --all-files';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-golangci-hook-green',
      description: 'The generated golangci-lint hook passes the healthy Go source.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'hook-golangci-lint');
      },
    },
    {
      name: 'mutation-golangci-hook-caught',
      description: 'A native ineffassign violation must turn the owning hook red.',
      kind: 'mutation',
      async run(repo: any) {
        await plantGoFile(
          repo,
          'lib/**/*.go',
          'probe_lint.go',
          'func ProbeLint() int { value := 1; value = 2; return value }',
        );
        await expectRed(repo, gate, 'hook-golangci-lint');
      },
    },
  ],
};
