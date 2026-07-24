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
        await repo.patch('lib/note/note.go', {
          find: 'func Slug(value string) string {\n\treturn strings.Join(strings.Fields(strings.ToLower(value)), "-")\n}',
          replace:
            'func Slug(value string) string {\n\tnormalized := value\n\tnormalized = value\n\treturn strings.Join(strings.Fields(strings.ToLower(normalized)), "-")\n}',
        });
        await expectRed(repo, gate, 'hook-golangci-lint');
      },
    },
  ],
};
