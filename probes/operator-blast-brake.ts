import { expectGreen, expectRed } from './lib/helpers.ts';

const cmd = 'nix develop .#ci -c go test -count=1 -run TestNoteBlastBrakeTrips ./tests/int/operator/';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-operator-blast-brake-green',
      description: 'An over-cap destructive batch trips the blast brake and writes nothing (envtest).',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, cmd, 'operator-blast-brake');
      },
    },
    {
      name: 'mutation-operator-blast-brake-caught',
      description: 'Bypassing the percentage cap must let the destructive batch through (red).',
      kind: 'mutation',
      async run(repo: any) {
        await repo.patch('lib/operator/brake/brake.go', {
          find: 'if deletes*100 > capPercent*existing {',
          replace: 'if false {',
        });
        await expectRed(repo, cmd, 'operator-blast-brake');
      },
    },
  ],
};
