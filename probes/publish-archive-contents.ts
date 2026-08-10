import { expectGreen, expectRed } from './lib/helpers.ts';

// Gate: the publishable archive (as reported by the offline-safe
// `flutter pub publish --dry-run --skip-validation` archive builder)
// must ship the consumer usage skill. Sabotage adds `skills/` to `.pubignore`
// and proves the skill drops out of the archive listing.
//
// The `|| true` this replaced was a FALSE GREEN: it swallowed the archive
// builder's own exit code, so a dry run that failed outright still reached the
// grep with whatever partial output it had emitted. `&&` makes the builder's
// refusal the probe's refusal. `grep -F` because the needle is a literal.
const DRY_RUN_HAS_SKILL =
  'nix develop .#ci --no-write-lock-file -c bash -lc \'cd packages/diene_e2e && out=$(flutter pub publish --dry-run --skip-validation 2>&1) && printf "%s\\n" "$out" | grep -F -q diene-e2e-usage\'';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: [
      'nix develop .#ci --no-write-lock-file -c flutter pub get --offline || nix develop .#ci --no-write-lock-file -c flutter pub get',
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
        const pubignore = 'packages/diene_e2e/.pubignore';
        await repo.write(pubignore, `${await repo.read(pubignore)}\nskills/\n`);
        await expectRed(repo, DRY_RUN_HAS_SKILL, 'publish-archive-contents');
      },
    },
  ],
};
