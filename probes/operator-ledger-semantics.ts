import { expectGreen, expectRed } from './lib/helpers.ts';

// Runs against a real testcontainers MinIO backend (Docker); the closer runs it
// in the host quiet window.
const cmd = 'nix develop .#ci -c go test -count=1 -run TestMinioLedgerLifecycle ./tests/int/operator/';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-operator-ledger-semantics-green',
      description: 'The durable ledger honours intent->create->confirm plus orphan/adopt-back (MinIO).',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, cmd, 'operator-ledger-semantics');
      },
    },
    {
      name: 'mutation-operator-ledger-semantics-caught',
      description: 'Bypassing ledger-lookup-first on reapply must break adopt-back (red).',
      kind: 'mutation',
      async run(repo: any) {
        await repo.patch('lib/operator/ledger/ledger.go', {
          find: 'if ok {',
          replace: 'if ok && false {',
        });
        await expectRed(repo, cmd, 'operator-ledger-semantics');
      },
    },
  ],
};
