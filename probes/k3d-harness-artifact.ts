export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'presence-k3d-harness-artifact',
      description: 'The reusable k3d harness script exists and is documented as reusable.',
      kind: 'baseline',
      async run(repo: any) {
        if ((await repo.glob('scripts/local/operator-e2e.sh')).length !== 1) {
          throw new Error('missing reusable harness scripts/local/operator-e2e.sh');
        }
        const doc = await repo.read('docs/domain/operator-conventions.md');
        if (!doc.includes('operator-e2e.sh')) {
          throw new Error('harness reuse is not documented in the operator conventions');
        }
      },
    },
  ],
};
