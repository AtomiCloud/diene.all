// A regex over the config would report a malformed document as proven, so something has to parse it.
function parseYaml(source: string): any {
  const runtime = (globalThis as any).Bun;
  if (typeof runtime?.YAML?.parse !== 'function') {
    throw new Error('no YAML parser available in the probe runtime (expected Bun.YAML.parse)');
  }
  return runtime.YAML.parse(source);
}

const tiers = ['unit', 'int'];

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'presence-bun-codecov-config',
      description: 'The codecov config parses, carries a scoped per-tier flag, and stays informational.',
      kind: 'baseline',
      async run(repo: any) {
        const config = parseYaml(await repo.read('codecov.yml'));

        for (const tier of tiers) {
          const flag = config?.flags?.[tier];
          if (!flag) {
            throw new Error(`codecov.yml declares no '${tier}' flag`);
          }
          if (flag.carryforward !== true) {
            throw new Error(`the codecov '${tier}' flag does not carry coverage forward`);
          }
          if (!Array.isArray(flag.paths) || flag.paths.length === 0) {
            throw new Error(`the codecov '${tier}' flag declares no scope, so its trend has no subject`);
          }
        }

        for (const status of ['project', 'patch']) {
          if (config?.coverage?.status?.[status]?.default?.informational !== true) {
            throw new Error(`the codecov ${status} status is not informational, so it can block CI`);
          }
        }

        // The flags only mean anything if a suite actually uploads under them.
        const workflows = await repo.glob('.github/workflows/**/*.{yaml,yml}');
        const uploading = [];
        for (const path of workflows) {
          const source = await repo.read(path);
          if (source.includes('codecov/codecov-action') && source.includes('flags:')) {
            uploading.push(path);
          }
        }
        if (uploading.length === 0) {
          throw new Error('no workflow uploads coverage under a codecov flag');
        }
      },
    },
  ],
};
