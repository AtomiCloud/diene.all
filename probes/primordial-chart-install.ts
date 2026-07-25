export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-primordial-chart-install-green',
      description:
        'Both charts install into one uniquely named local k3d cluster; this row asserts the primordial release and its T3 CR set.',
      kind: 'baseline',
      async run(repo: any) {
        const result = await repo.exec("nix develop .#ci -c bash -lc './scripts/validate/chart-install.sh'", {
          timeoutMs: 900000,
        });
        if (result.exitCode !== 0) {
          throw new Error(`chart install smoke failed: ${result.stderr || result.stdout}`);
        }
        if (!result.stdout.includes('bunconsumer-primordial')) {
          throw new Error('primordial chart release missing from helm list evidence');
        }
        if (!result.stdout.includes('platformdependency.fleet.atomi.cloud/bunconsumer-lapras')) {
          throw new Error('PlatformDependency CR missing from install evidence');
        }
      },
    },
  ],
};
