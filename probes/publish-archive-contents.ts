import { expectGreen, expectRed } from './lib/helpers.ts';

// Gate: the publishable archive (as reported by the offline-safe
// `dart pub publish --dry-run --skip-validation` archive builder)
// must ship the consumer usage skill. Sabotage adds `skills/` to `.pubignore`
// and proves the skill drops out of the archive listing.
const DRY_RUN_HAS_SKILL =
  'nix develop .#ci --no-write-lock-file -c bash -lc \'cd packages/diene_dart_lib && out=$(dart pub publish --dry-run --skip-validation 2>&1) && printf "%s\\n" "$out" | grep -F -q diene-dart-lib-usage\'';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: ['nix develop .#ci --no-write-lock-file -c dart pub get --offline'],
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
        const pubignore = 'packages/diene_dart_lib/.pubignore';
        await repo.write(pubignore, `${await repo.read(pubignore)}\nskills/\n`);
        await expectRed(repo, DRY_RUN_HAS_SKILL, 'publish-archive-contents');
      },
    },
  ],
};
