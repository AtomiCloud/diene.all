import { expectGreen, expectRed } from './lib/helpers.ts';

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
        await repo.patch('lib/operator/note/note.go', {
          find: 'func CopyName(owner string, i int32) string {\n\treturn fmt.Sprintf("%s-copy-%d", owner, i)\n}',
          replace:
            'func CopyName(owner string, i int32) string {\n\tname := owner\n\tname = owner\n\treturn fmt.Sprintf("%s-copy-%d", name, i)\n}',
        });
        await expectRed(repo, gate, 'hook-golangci-lint');
      },
    },
  ],
};
