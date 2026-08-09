const required = [
  'docs/standards/frontend-ux/index.md',
  'docs/standards/frontend-ux/languages/dart.md',
  'docs/standards/frontend-ui-trend/index.md',
  'docs/standards/frontend-ui-trend/languages/dart.md',
  'docs/domain/identity.md',
  'assets/brand/tokens.json',
  '.claude/skills/frontend-ux-check/SKILL.md',
  '.claude/skills/vision-loop/SKILL.md',
  '.claude/skills/write-search-bar/SKILL.md',
  '.claude/skills/write-screen/SKILL.md',
  '.claude/skills/write-protected-screen/SKILL.md',
  '.claude/skills/write-onboarding-gated-app/SKILL.md',
  '.claude/skills/write-form/SKILL.md',
  'docs/standards/search-bar/languages/dart.md',
  'docs/standards/screen/languages/dart.md',
  'docs/standards/protected-screen/languages/dart.md',
  'docs/standards/onboarding-gated-app/languages/dart.md',
  'docs/standards/form/languages/dart.md',
  'lib/widgets/async_button.dart',
  'lib/widgets/bottom_sheet_selector.dart',
  'lib/widgets/amount_input.dart',
  'lib/widgets/problem_visualizer.dart',
  'lib/widgets/persistent_form.dart',
  'lib/widgets/safe_area_shell.dart',
] as const;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'presence-frontend-ux-artifacts',
      description: 'The UX doctrine, trend, identity, thin skills, tokens, and baseline widgets exist.',
      kind: 'baseline',
      async run(repo: any) {
        for (const path of required) {
          if ((await repo.glob(path)).length !== 1) {
            throw new Error(`missing Flutter UX artifact: ${path}`);
          }
        }
        if ((await repo.glob('docs/standards/*/languages/dart.md')).length < 18) {
          throw new Error('the Flutter template does not register Dart across its standards');
        }
      },
    },
  ],
};
