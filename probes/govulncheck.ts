import { expectGreen, expectRedWithDiagnostic } from './lib/helpers.ts';

// Both rows drive `scripts/ci/vuln.sh`, the exact entrypoint
// `⚡reusable-go-vuln.yaml` runs. The thinner `scripts/local/vuln.sh` skips the
// wrapper's `scripts/ci/setup.sh` step, so binding it would leave the CI lane's
// own composition — setup ordering included — unproven by either row.
const ciVulnGate = './scripts/ci/vuln.sh';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-govulncheck-green',
      description: 'The real blocking govulncheck CI entrypoint accepts the healthy module.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, `nix develop .#ci -c ${ciVulnGate}`, 'govulncheck', 600000);
      },
    },
    {
      name: 'mutation-govulncheck-caught',
      description: 'Routing the pinned vulnerable fixture through the scanner double must redden the CI gate.',
      kind: 'mutation',
      async run(repo: any) {
        // The fixture env is handed to the CI wrapper, not to the inner script,
        // so the row also proves the wrapper forwards the scanner selection
        // instead of pinning a scanner of its own.
        await expectRedWithDiagnostic(
          repo,
          `nix develop .#ci -c env GOVULNCHECK_BIN=./tests/fixtures/govulncheck-double.sh GOVULNCHECK_TARGET=./tests/fixtures/vulnerable ${ciVulnGate}`,
          'govulncheck',
          /GO-2021-0113: pinned vulnerable fixture detected/,
          600000,
        );
      },
    },
  ],
};
