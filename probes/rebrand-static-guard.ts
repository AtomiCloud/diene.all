import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-rebrand-static-guard-green',
      description: 'Identity, branding, and SSO/auth values stay config-driven; the static guard passes.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          "nix develop .#ci -c bash -lc './scripts/local/setup.sh && ./scripts/validate/rebrand.sh'",
          'rebrand-static-guard',
        );
      },
    },
    {
      name: 'mutation-rebrand-static-guard-caught',
      description: 'One hardcoded identity value outside the composition root turns the guard red.',
      kind: 'mutation',
      async run(repo: any) {
        const settings = Bun.YAML.parse(await repo.read('config/settings.yaml')) as {
          app?: { service?: unknown };
        };
        const service = settings.app?.service;
        if (typeof service !== 'string' || service.length === 0) {
          throw new Error('could not resolve the configured service identity');
        }
        const targets = await repo.glob('src/adapters/**/*.ts');
        if (targets.length === 0) {
          throw new Error('no structural adapter target found');
        }
        let target: { path: string; source: string } | undefined;
        for (const path of targets.sort()) {
          const source = await repo.read(path);
          if (source.includes("this.name = 'AdapterError';")) {
            target = { path, source };
            break;
          }
        }
        if (!target) {
          throw new Error('no used adapter error identity found');
        }
        await repo.write(
          target.path,
          target.source.replace("this.name = 'AdapterError';", `this.name = '${service}';`),
        );
        await expectRed(
          repo,
          "nix develop .#ci -c bash -lc './scripts/local/setup.sh && ./scripts/validate/rebrand.sh'",
          'rebrand-static-guard',
        );
      },
    },
  ],
};
