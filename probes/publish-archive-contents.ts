import { expectGreen, expectRed } from './lib/helpers.ts';

// Gate: the publishable archive (as reported by `dart pub publish --dry-run`)
// must ship the consumer usage skill. Sabotage adds `skills/` to `.pubignore`
// and proves the skill drops out of the archive listing.
//
// The dry run's own exit status is REQUIRED before its output is inspected. The
// earlier form swallowed it with `|| true`, so a dry run that failed outright
// could still be read as an archive-listing success whenever its error text
// happened to mention the skill name — the gate would have proved nothing about
// the archive while reporting green.
const DRY_RUN_HAS_SKILL =
  'nix develop .#ci --no-write-lock-file -c bash -lc \'cd packages/diene_config && out=$(dart pub publish --dry-run 2>&1); echo "$out" | grep -q diene-config-usage\'';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: [
      'nix develop .#ci --no-write-lock-file -c dart pub get --offline || nix develop .#ci --no-write-lock-file -c dart pub get',
    ],
  },
  probes: [
    {
      name: 'baseline-publish-archive-contents-green',
      description: 'the dry-run archive listing includes the usage skill',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, DRY_RUN_HAS_SKILL, 'publish-archive-contents');
      },
    },
    {
      name: 'mutation-publish-archive-contents-caught',
      description: 'the archive listing loses the usage skill once skills/ is pubignored',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const pubignore = 'packages/diene_config/.pubignore';
        await repo.write(pubignore, `${await repo.read(pubignore)}\nskills/\n`);
        await expectRed(repo, DRY_RUN_HAS_SKILL, 'publish-archive-contents');
      },
    },
  ],
};
