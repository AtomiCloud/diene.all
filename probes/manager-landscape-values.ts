export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'presence-manager-landscape-values',
      description: 'The required per-landscape values files exist for the manager chart.',
      kind: 'baseline',
      async run(repo: any) {
        for (const landscape of ['lapras', 'pichu', 'pikachu', 'raichu', 'amphoros']) {
          const paths = await repo.glob(`infra/root_chart/values.${landscape}.yaml`);
          if (paths.length !== 1) {
            throw new Error(`missing landscape values file: values.${landscape}.yaml`);
          }
        }
      },
    },
  ],
};
