import { expectGreen, expectRed } from './lib/helpers.ts';

const cmd = 'nix develop .#ci -c go test -count=1 -run TestNoteConvergesToReady ./tests/int/operator/';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-operator-reconcile-green',
      description: 'A toy Note reconciles to Ready with its owned ConfigMaps converged (envtest).',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, cmd, 'operator-reconcile');
      },
    },
    {
      name: 'mutation-operator-reconcile-caught',
      description: 'Bypassing the owned-resource apply must leave the Note un-converged (red).',
      kind: 'mutation',
      expectedImpact: ['sample-domain-journey', 'operator-multi-controller-wiring'],
      async run(repo: any) {
        await repo.patch('adapters/operator/controllers/note_controller.go', {
          find: 'for _, u := range dec.Upserts {',
          replace: 'for _, u := range dec.Upserts[:0] {',
        });
        await expectRed(repo, cmd, 'operator-reconcile');
      },
    },
  ],
};
