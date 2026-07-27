import { expectGreen, expectRed } from './lib/helpers.ts';

// Gate: the publishable archive (as reported by `dart pub publish --dry-run`)
// must ship the consumer usage skill. Sabotage adds `skills/` to `.pubignore`
// and proves the skill drops out of the archive listing.
const DRY_RUN_HAS_SKILL =
  'nix develop .#ci --no-write-lock-file -c bash -lc \'cd packages/diene_api_engine && out=$(dart pub publish --dry-run 2>&1 || true); echo "$out" | grep -q diene-api-engine-usage\'';

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
        const pubignore = 'packages/diene_api_engine/.pubignore';
        await repo.write(pubignore, `${await repo.read(pubignore)}\nskills/\n`);
        await expectRed(repo, DRY_RUN_HAS_SKILL, 'publish-archive-contents');
      },
    },
  ],
};
