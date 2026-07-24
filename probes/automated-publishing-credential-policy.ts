// Gate (static policy): publishing uses pub.dev Automated Publishing via GitHub
// OIDC — the reusable publish workflow must request `id-token: write`, pin the
// `pub.dev` environment, and carry no long-lived credential. Sabotage removes
// the OIDC token permission and proves the policy check no longer holds.
const REUSABLE_PUBLISH = '.github/workflows/⚡reusable-publish.yaml';

function credentialPolicyHolds(source: string): boolean {
  const hasOidc = source.includes('id-token: write');
  const hasEnvironment = source.includes('environment: pub.dev');
  const hasStaticCredential = /PUB_CREDENTIALS|pub-credentials|credentials\.json|PUB_TOKEN|accessToken/i.test(source);
  return hasOidc && hasEnvironment && !hasStaticCredential;
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'baseline-automated-publishing-credential-policy-green',
      description: 'the publish workflow requests OIDC, pins pub.dev, and ships no long-lived credential',
      kind: 'baseline',
      async run(repo: any) {
        if (!credentialPolicyHolds(await repo.read(REUSABLE_PUBLISH))) {
          throw new Error(
            'automated-publishing-credential-policy: publish workflow violates the OIDC credential policy',
          );
        }
      },
    },
    {
      name: 'mutation-automated-publishing-credential-policy-caught',
      description: 'the policy check detects the OIDC id-token permission being removed',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const source = await repo.read(REUSABLE_PUBLISH);
        if (!credentialPolicyHolds(source)) {
          throw new Error('automated-publishing-credential-policy: policy already broken before sabotage');
        }
        await repo.write(REUSABLE_PUBLISH, source.replace('id-token: write', 'id-token: none'));
        if (credentialPolicyHolds(await repo.read(REUSABLE_PUBLISH))) {
          throw new Error('automated-publishing-credential-policy: policy survived sabotage');
        }
      },
    },
  ],
};
