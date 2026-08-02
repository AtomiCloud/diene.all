import { expectGreen, expectRedWithDiagnostic, restoreProbeState } from './lib/helpers.ts';
import { plantGoFile } from './lib/go.ts';

const gate = 'nix develop .#ci -c pls test:int:coverage';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-integration-coverage-scoped',
      description: 'The integration coverprofile contains only adapter packages at threshold.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'integration-coverage-scope');
      },
    },
    {
      name: 'mutation-integration-coverage-caught',
      description: 'An uncovered adapter function must turn the integration ledger red.',
      kind: 'mutation',
      expectedImpact: ['deadcode-whole-repo', 'deadcode-production'],
      async run(repo: any) {
        const planted = await plantGoFile(
          repo,
          'adapters/**/*.go',
          'probe_uncovered.go',
          'func ProbeUncovered() int { return 1 }',
        );
        try {
          await expectRedWithDiagnostic(repo, gate, 'integration-coverage-scope', /int coverage .* is below/);
        } finally {
          await restoreProbeState(repo, [planted]);
        }
      },
    },
  ],
};
