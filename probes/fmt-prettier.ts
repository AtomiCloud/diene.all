import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-fmt-prettier-green',
      description: 'The treefmt Prettier member passes on Markdown and YAML.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix fmt --no-write-lock-file -- --ci --formatters prettier', 'fmt-prettier');
      },
    },
    {
      name: 'mutation-fmt-prettier-caught',
      description: 'A focused sabotage must turn the fmt-prettier mechanism red.',
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
        await repo.patch('.prettierrc.yaml', { find: 'arrowParens: avoid', replace: 'arrowParens:    avoid' });
        await expectRed(repo, 'nix fmt --no-write-lock-file -- --ci --formatters prettier', 'fmt-prettier');
      },
    },
  ],
};
