import { expectGreen, expectRedWithDiagnostic, restoreProbeState } from './lib/helpers.ts';
import { unformatGo } from './lib/go.ts';

const gate = 'nix develop .#ci -c pre-commit run treefmt --all-files';

// Accept treefmt's path-after-verb diagnostic, gofumpt's reformat diagnostic, and the older path-before-verb shape.
const goFormatting = /(file has changed path=|would reformat )\S+[.]go|[.]go.*(formatted|changed)/i;

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
      async run(repo: any) {
        const mutated = await unformatGo(repo);
        try {
          await expectRedWithDiagnostic(repo, gate, 'precommit-treefmt-gofumpt', goFormatting);
        } finally {
          await restoreProbeState(repo, [mutated]);
        }
      },
    },
  ],
};
