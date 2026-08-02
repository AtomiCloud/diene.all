export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'presence-probe-artifacts',
      description: 'Every declared feature has a probe definition and the shared helper library exists.',
      kind: 'baseline',
      async run(repo: any) {
        const features = JSON.parse(await repo.read('probes/features.json'));
        for (const feature of features) {
          const paths = await repo.glob(`probes/${feature.name}.ts`);
          if (paths.length !== 1) {
            throw new Error(`missing probe definition for ${feature.name}`);
          }
        }
        const declared = new Set(features.map((feature: { name: string }) => feature.name));
        for (const path of await repo.glob('probes/*.ts')) {
          const name = path.replace(/^probes\//, '').replace(/\.ts$/, '');
          if (!declared.has(name)) {
            throw new Error(`probe definition has no feature row: ${name}`);
          }
        }
        if ((await repo.glob('probes/lib/helpers.ts')).length !== 1) {
          throw new Error('shared probe helpers are missing');
        }
      },
    },
  ],
};
