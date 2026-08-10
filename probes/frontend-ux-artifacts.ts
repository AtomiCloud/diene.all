// Cost: light (<5s) — a glob sweep, no shell.
//
// The UX standards, the two review skills, and the identity brief are what make
// "does this look right" a repeatable check rather than a matter of taste; the
// rule-defaulting components are where those rules are actually spent. Q-D6 rules
// out golden and screenshot evidence anywhere in this tree, so presence of the
// written rules plus the components that encode them is the honest claim here.
const requiredArtifacts = [
  'docs/standards/frontend-ux/index.md',
  'docs/standards/frontend-ux/patterns.md',
  'docs/standards/frontend-ui-trend/index.md',
  '.claude/skills/frontend-ux-check/SKILL.md',
  '.claude/skills/vision-loop/SKILL.md',
  'docs/domain/identity.md',
  'src/lib/tokens/index.ts',
  'src/components/ui/AsyncButton.tsx',
  'src/components/ui/Field.tsx',
  'src/components/ui/SelectSheet.tsx',
  'src/components/ui/AmountInput.tsx',
  'src/components/ui/ErrorTier.tsx',
  'src/components/ui/Skeleton.tsx',
  'src/components/shell/SafeAreaShell.tsx',
] as const;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'presence-frontend-ux-artifacts',
      description:
        'The frontend UX and UI-trend standards, both review skills, the identity brief, the token source, and every rule-defaulting component exist.',
      kind: 'baseline',
      async run(repo: any) {
        for (const artifact of requiredArtifacts) {
          if ((await repo.glob(artifact)).length !== 1) {
            throw new Error(`missing frontend-UX payload artifact: ${artifact}`);
          }
        }
      },
    },
  ],
};
