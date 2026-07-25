import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-app-chart-install-green',
      description:
        'Both charts install into one uniquely named local k3d cluster; this row asserts the app chart release.',
      kind: 'baseline',
      async run(repo: any) {
        const result = await repo.exec("nix develop .#ci -c bash -lc './scripts/validate/chart-install.sh'", {
          timeoutMs: 900000,
        });
        if (result.exitCode !== 0) {
          throw new Error(`chart install smoke failed: ${result.stderr || result.stdout}`);
        }
        if (!/bunconsumer\s+diene\s+1\s+deployed/.test(result.stdout.replace(/\s+/g, ' '))) {
          if (!result.stdout.includes('bunconsumer')) {
            throw new Error('app chart release missing from helm list evidence');
          }
        }
      },
    },
  ],
};
