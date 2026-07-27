import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<20s). The lint is invoked through the repository's own lint
// surface (`pre-commit run a-i18n-keys`, the hook registered in nix/pre-commit.nix)
// so the gate proves the check is WIRED, not merely present as a script.
const command = 'nix develop .#ci -c pre-commit run a-i18n-keys --all-files';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-i18n-missing-key-green',
      description:
        'Every locale catalogue carries exactly the reference locale key set, enforced through the repository lint surface.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'i18n-missing-key');
      },
    },
    {
      name: 'mutation-i18n-missing-key-caught',
      description: 'A key present in the reference locale and missing from another turns the missing-key lint red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // next-intl falls back silently, so a missing key ships as English text in
        // a German page — visible to users, invisible to the build.
        const path = 'messages/de.json';
        const catalogue = JSON.parse(await repo.read(path));
        const section = Object.keys(catalogue)[0];
        const keys = Object.keys(catalogue[section]);
        if (keys.length === 0) throw new Error('no de.json key available to remove');
        delete catalogue[section][keys[0]];
        await repo.write(path, `${JSON.stringify(catalogue, null, 2)}\n`);
        await expectBunRed(repo, command, 'i18n-missing-key');
      },
    },
  ],
};
