import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-hook-shellcheck-green',
      description: 'The generated shellcheck hook passes on the untouched scripts.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c pre-commit run a-shellcheck --all-files', 'hook-shellcheck');
      },
    },
    {
      name: 'mutation-hook-shellcheck-caught',
      description: 'A focused sabotage must turn the hook-shellcheck mechanism red.',
      kind: 'mutation',
      // DELIBERATE DIVERGENCE FROM THE PARENT - do not "restore" byte-identity.
      // This probe is byte-identical to bun-base upstream, so ownership-by-bytes would
      // put this declaration there. It CANNOT live there: the control it names does not
      // exist on bun-base, and declaring it would be a dangling reference inherited by
      // every descendant. Ruled by noel 2026-07-29 to declare on the leaf and record the
      // divergence. expectedImpact names FEATURES, features are PER-TEMPLATE, so a static
      // list in a shared file cannot be correct on all surfaces - the file was never truly
      // shared, only coincidentally identical. Upstream fix filed: sulfone.lite #23 /
      // PROBES.md Gap 6 (absent feature should resolve INAPPLICABLE, not dangling).
      // MEASURED: control output was the playwright host-requirements notice - it ran and failed.
      expectedImpact: ['resize-fluid-i18n'],
      async run(repo: any) {
        const source = await repo.read('scripts/release/bump.sh');
        await repo.write('scripts/release/bump.sh', `${source}\necho $UNQUOTED\n`);
        await expectRed(repo, 'nix develop .#ci -c pre-commit run a-shellcheck --all-files', 'hook-shellcheck');
      },
    },
  ],
};
