import { expectGreen, expectRed } from './lib/helpers.ts';

const cmd = 'nix develop .#ci -c go test -count=1 -run TestNoteConvergesToReady ./tests/int/operator/';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-operator-status-conditions-green',
      description: 'A reconciled toy Note reports the standard Ready condition (envtest).',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, cmd, 'operator-status-conditions');
      },
    },
    {
      name: 'mutation-operator-status-conditions-caught',
      description: 'Removing the Ready-condition update must fail the condition assertion (red).',
      kind: 'mutation',
      expectedImpact: ['operator-multi-controller-wiring'],
      async run(repo: any) {
        await repo.patch('adapters/operator/controllers/note_controller.go', {
          find: 'r.publish(note, dec.OwnedCount, dec.Conditions, dec.Events)',
          replace: 'r.publish(note, dec.OwnedCount, nil, dec.Events)',
        });
        await expectRed(repo, cmd, 'operator-status-conditions');
      },
    },
  ],
};
