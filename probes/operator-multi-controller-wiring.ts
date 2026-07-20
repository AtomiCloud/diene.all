import { expectGreen, expectRed } from './lib/helpers.ts';

const cmd = 'nix develop .#ci -c go test -count=1 -run TestMultiControllerWiring ./tests/int/operator/';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-operator-multi-controller-wiring-green',
      description: 'Both enabled toy controllers register independently on one manager (envtest).',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, cmd, 'operator-multi-controller-wiring');
      },
    },
    {
      name: 'mutation-operator-multi-controller-wiring-caught',
      description: 'Collapsing the second controller onto the first name must break wiring (red).',
      kind: 'mutation',
      async run(repo: any) {
        await repo.patch('adapters/operator/controllers/journal_controller.go', {
          find: 'const journalController = "journal"',
          replace: 'const journalController = "note"',
        });
        await expectRed(repo, cmd, 'operator-multi-controller-wiring');
      },
    },
  ],
};
