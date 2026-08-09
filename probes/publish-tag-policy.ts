// Gate (static policy): the release pipeline (cd.yaml) must trigger only on
// semantic-version release tags (`v[0-9]+.[0-9]+.[0-9]+`). Sabotage rewrites the
// trigger to a non-release pattern and proves the policy check no longer holds.
const CD = '.github/workflows/cd.yaml';
const TAG_PATTERN = 'v[0-9]+.[0-9]+.[0-9]+';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'baseline-publish-tag-policy-green',
      description: 'cd.yaml triggers on the semantic-version release tag pattern',
      kind: 'baseline',
      async run(repo: any) {
        const source = await repo.read(CD);
        if (!source.includes(TAG_PATTERN)) {
          throw new Error('publish-tag-policy: cd.yaml does not trigger on the release tag pattern');
        }
      },
    },
    {
      name: 'mutation-publish-tag-policy-caught',
      description: 'the policy check detects the release tag trigger being replaced',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const source = await repo.read(CD);
        if (!source.includes(TAG_PATTERN)) {
          throw new Error('publish-tag-policy: tag pattern missing before sabotage');
        }
        await repo.write(CD, source.split(TAG_PATTERN).join('main'));
        if ((await repo.read(CD)).includes(TAG_PATTERN)) {
          throw new Error('publish-tag-policy: tag pattern survived sabotage');
        }
      },
    },
  ],
};
