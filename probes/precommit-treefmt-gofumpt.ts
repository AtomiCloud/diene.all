import { expectGreen, expectRedWithDiagnostic } from './lib/helpers.ts';
import { unformatGo } from './lib/go.ts';

const gate = 'nix develop .#ci -c pre-commit run treefmt --all-files';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-treefmt-gofumpt-hook-green',
      description: 'The generated treefmt hook passes its Go formatter member.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'precommit-treefmt-gofumpt');
      },
    },
    {
      name: 'mutation-treefmt-gofumpt-hook-caught',
      description: 'An unformatted Go declaration must turn the generated treefmt hook red.',
      kind: 'mutation',
      // The same violation reaches the direct treefmt entrypoint, and the hook
      // fails as one unit, so every inherited member row reddens with it.
      expectedImpact: [
        'fmt-gofumpt',
        'precommit-treefmt-actionlint',
        'precommit-treefmt-nixfmt',
        'precommit-treefmt-prettier',
        'precommit-treefmt-shfmt',
      ],
      async run(repo: any) {
        await unformatGo(repo);
        await expectRedWithDiagnostic(
          repo,
          gate,
          'precommit-treefmt-gofumpt',
          /[.]go.*(formatted|changed)|would reformat/i,
        );
      },
    },
  ],
};
