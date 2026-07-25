import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<20s) — config read plus schema check, no build.
const command = "nix develop .#ci -c bash -lc './scripts/local/setup.sh && bun scripts/validate/pwa-manifest.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-pwa-manifest-green',
      description:
        'The manifest is derived entirely from branding config and carries every member an installable PWA requires.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'pwa-manifest');
      },
    },
    {
      name: 'mutation-pwa-manifest-caught',
      description: 'A blank branding short name turns the manifest check red.',
      kind: 'mutation',
      expectedImpact: ['config-merge', 'rebrand-static'],
      async run(repo: any) {
        // A blank short_name installs an app with no label under its icon; the page
        // itself renders perfectly, so nothing but this check sees it.
        const path = 'config/config.yaml';
        const source = await repo.read(path);
        await repo.write(path, source.replace(/^(\s*shortName:).*$/m, "$1 ''"));
        await expectBunRed(repo, command, 'pwa-manifest');
      },
    },
  ],
};
