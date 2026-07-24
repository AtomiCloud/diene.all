import { expectGreen, expectRed } from './lib/helpers.ts';

const cmd = "nix develop .#ci -c go test -count=1 -run '^TestMultiControllerWiring$' ./tests/int/operator/";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-operator-multi-controller-wiring-green',
      description:
        'The real enable flags register both controllers on a started envtest manager, and Note plus Journal converge independently.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, cmd, 'operator-multi-controller-wiring');
      },
    },
    {
      name: 'mutation-operator-multi-controller-wiring-caught',
      description:
        'Disabling Journal registration through the same enable-flag path must leave Journal unconverged and turn acceptance red.',
      kind: 'mutation',
      async run(repo: any) {
        await repo.patch('internal/operatorruntime/runtime.go', {
          find: 'if config.EnableJournal {',
          replace: 'if false && config.EnableJournal {',
        });
        await expectRed(repo, cmd, 'operator-multi-controller-wiring');
      },
    },
  ],
};
