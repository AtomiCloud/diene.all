// Presence: the probe registry is internally consistent — features.json parses,
// every declared feature has a matching probes/<name>.ts, and every top-level
// probe module has a feature row (1:1).
export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'baseline-probe-inventory-consistent',
      description: 'features.json and the probes/ modules are a consistent 1:1 set',
      kind: 'baseline',
      async run(repo: any) {
        const features = JSON.parse(await repo.read('probes/features.json'));
        if (!Array.isArray(features) || features.length === 0) {
          throw new Error('probe-inventory: features.json is not a non-empty array');
        }
        for (const feature of features) {
          if ((await repo.glob(`probes/${feature.name}.ts`)).length !== 1) {
            throw new Error(`probe-inventory: feature ${feature.name} has no probes/${feature.name}.ts`);
          }
        }
        const declared = new Set(features.map((feature: any) => feature.name));
        for (const module of await repo.glob('probes/*.ts')) {
          const name = module.replace(/^probes\//, '').replace(/\.ts$/, '');
          if (!declared.has(name)) {
            throw new Error(`probe-inventory: probe module ${name} has no feature row`);
          }
        }
      },
    },
  ],
};
