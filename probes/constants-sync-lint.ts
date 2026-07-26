import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-constants-sync-green',
      description: 'Typed constants mirror every keyed-adapter configuration key.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          "nix develop .#ci -c bash -lc './scripts/local/setup.sh && ./scripts/validate/constants-sync.sh'",
          'constants-sync-lint',
        );
      },
    },
    {
      name: 'mutation-constants-sync-caught',
      description: 'A keyed-adapter config key added without its typed constant turns the lint red.',
      kind: 'mutation',
      async run(repo: any) {
        const source = await repo.read('config/settings.yaml');
        const patched = source.replace(/^postgres:$/m, 'postgres:\n  SABOTAGE: {}');
        if (patched === source) {
          throw new Error('no structural postgres block found in config/settings.yaml');
        }
        await repo.write('config/settings.yaml', patched);
        await expectRed(
          repo,
          "nix develop .#ci -c bash -lc './scripts/local/setup.sh && ./scripts/validate/constants-sync.sh'",
          'constants-sync-lint',
        );
      },
    },
  ],
};
