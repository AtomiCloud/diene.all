import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<20s) — a source scan against the config values, no build.
const command = "nix develop .#ci -c bash -lc './scripts/local/setup.sh && bun scripts/validate/rebrand-static.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-rebrand-static-green',
      description:
        'No branding, SEO, or auth identity value appears as a literal in source: a rebrand is a config edit and nothing else.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'rebrand-static');
      },
    },
    {
      name: 'mutation-rebrand-static-caught',
      description: 'A hardcoded canonical base URL in a page turns the rebrand guard red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // The page renders identically today. The cost lands on whoever rebrands or
        // re-hosts the template later and finds one landscape's URL baked into a
        // component — which is precisely the drift the guard scans for.
        const baseUrl = /baseUrl:\s*(\S+)/.exec(await repo.read('config/config.yaml'))?.[1];
        if (baseUrl === undefined) throw new Error('no seo.baseUrl found in config/config.yaml');
        const path = 'src/app/[locale]/page.tsx';
        const source = await repo.read(path);
        await repo.write(
          path,
          source.replace(
            '<p className="text-lg',
            `<link rel="canonical" href="${baseUrl}" />\n      <p className="text-lg`,
          ),
        );
        await expectBunRed(repo, command, 'rebrand-static');
      },
    },
  ],
};
