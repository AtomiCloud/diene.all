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
        const path = targets.sort()[0];
        const source = await repo.read(path);
        await repo.write(path, `${source.trimEnd()}\n\nexport const HARDCODED_IDENTITY = '${service}';\n`);
        await expectRed(
          repo,
          "nix develop .#ci -c bash -lc './scripts/local/setup.sh && ./scripts/validate/rebrand.sh'",
          'rebrand-static-guard',
        );
      },
    },
  ],
};
