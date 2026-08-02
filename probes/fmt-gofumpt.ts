import { expectGreen, expectRedWithDiagnostic } from './lib/helpers.ts';
import { unformatGo } from './lib/go.ts';

const gate = 'nix fmt --no-write-lock-file -- --ci --formatters gofumpt';

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
      async run(repo: any) {
        await unformatGo(repo);
        await expectRedWithDiagnostic(repo, gate, 'fmt-gofumpt', /[.]go.*(formatted|changed)|would reformat/i);
      },
    },
  ],
};
