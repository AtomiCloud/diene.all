import { expectGreen, expectRed } from './lib/helpers.ts';

const cmd = 'nix develop .#ci -c go test -count=1 -run TestNoteObserveWouldApply ./tests/int/operator/';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-operator-observe-no-write-green',
      description: 'Observe mode reports the plan and performs zero owned-resource writes (envtest).',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, cmd, 'operator-observe-no-write');
      },
    },
    {
      name: 'mutation-operator-observe-no-write-caught',
      description: 'Letting a write proceed under observe mode must fail the no-write safety test (red).',
      kind: 'mutation',
      async run(repo: any) {
        await repo.patch('adapters/operator/controllers/note_controller.go', {
          find: 'if r.Observe {',
          replace: 'if false {',
        });
        await expectRed(repo, cmd, 'operator-observe-no-write');
      },
    },
  ],
};
