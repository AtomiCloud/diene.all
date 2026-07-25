import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-govulncheck-green',
      description: 'The real blocking govulncheck entrypoint accepts the healthy module.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c ./scripts/local/vuln.sh', 'govulncheck');
      },
    },
    {
      name: 'mutation-govulncheck-caught',
      description: 'Routing the pinned vulnerable fixture through the scanner double must redden the gate.',
      kind: 'mutation',
      async run(repo: any) {
        await expectRed(
          repo,
          'nix develop .#ci -c env GOVULNCHECK_BIN=./tests/fixtures/govulncheck-double.sh GOVULNCHECK_TARGET=./tests/fixtures/vulnerable ./scripts/local/vuln.sh',
          'govulncheck',
        );
      },
    },
  ],
};
