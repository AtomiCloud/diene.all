import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-skills-sync-green',
      description: 'The universal skills synchronizer self-cleans and is idempotent on its second run.',
      kind: 'baseline',
      async run(repo: any) {
        await repo.write('.claude/skills/vendor/stale/SKILL.md', 'stale\n');
        await expectGreen(
          repo,
          `nix develop .#ci -c bash -c 'first="$(mktemp -d)"; second="$(mktemp -d)"; trap "rm -rf \\"$first\\" \\"$second\\"" EXIT; ./scripts/local/skills-sync.sh; test ! -e .claude/skills/vendor/stale; cp -R .claude/skills/vendor/. "$first"/; ./scripts/local/skills-sync.sh; cp -R .claude/skills/vendor/. "$second"/; diff -ru "$first" "$second"'`,
          'skills-sync',
        );
      },
    },
  ],
};
