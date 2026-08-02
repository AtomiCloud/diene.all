import { expectGreen, expectRedWithDiagnostic, restoreProbeState } from './lib/helpers.ts';
import { unformatGo } from './lib/go.ts';

const gate = 'nix fmt --no-write-lock-file -- --ci --formatters gofumpt';

// treefmt names the offending file as "file has changed path=<path>", a bare
// gofumpt run says "would reformat <path>", and older summaries put the verb
// after the path; the red must name a Go path in one of those shapes.
const goFormatting = /(file has changed path=|would reformat )\S+[.]go|[.]go.*(formatted|changed)/i;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-fmt-gofumpt-green',
      description: 'The direct gofumpt treefmt member passes healthy Go source.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'fmt-gofumpt');
      },
    },
    {
      name: 'mutation-fmt-gofumpt-caught',
      description: 'An unformatted Go declaration must turn the direct formatter red.',
      kind: 'mutation',
      // The violation is an in-place rewrite of a tracked lib source, and it is
      // reverted to HEAD the moment this row's own assertion has run, so every
      // other row still meets a clean tree: this mutation has no collateral.
      expectedImpact: [],
      async run(repo: any) {
        await unformatGo(repo);
        try {
          await expectRedWithDiagnostic(repo, gate, 'fmt-gofumpt', goFormatting);
        } finally {
          await restoreProbeState(repo, ['lib']);
        }
      },
    },
  ],
};
