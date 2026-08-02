import { expectGreen, expectRedWithDiagnostic } from './lib/helpers.ts';

// Drive the exact self-contained CI vulnerability entrypoint in both arms.
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
