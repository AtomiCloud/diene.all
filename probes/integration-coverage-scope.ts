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
      description: 'An adapter source the profile never measures must turn the integration ledger red.',
      kind: 'mutation',
      async run(repo: any) {
        // A statement-free declaration keeps the percentage at 100 and never reaches the profile, so only a derived source set sees it.
        const planted = await plantGoFile(
          repo,
          'adapters/**/*.go',
          'probe_uncovered.go',
          'type ProbeUncovered struct{}',
        );
        try {
          await expectRedWithDiagnostic(
            repo,
            gate,
            'integration-coverage-scope',
            /int coverage is missing 'adapters\/.*\.go'/,
          );
        } finally {
          await restoreProbeState(repo, [planted]);
        }
      },
    },
  ],
};
