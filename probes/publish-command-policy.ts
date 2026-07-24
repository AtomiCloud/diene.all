// Gate (static policy): the publish entrypoint (scripts/ci/publish.sh) must run
// the version guard first, operate from the member package directory, and force
// the pub.dev publish. Sabotage redirects the publish `cd` to the workspace root
// and proves the policy check no longer holds.
const PUBLISH_SH = 'scripts/ci/publish.sh';

function commandPolicyHolds(source: string): boolean {
  return (
    source.includes('scripts/validate/publish-version.sh') &&
    source.includes('packages/diene_dart_lib') &&
    source.includes('dart pub publish --force')
  );
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'baseline-publish-command-policy-green',
      description: 'publish.sh guards the version, cds into the member package, and force-publishes',
      kind: 'baseline',
      async run(repo: any) {
        if (!commandPolicyHolds(await repo.read(PUBLISH_SH))) {
          throw new Error('publish-command-policy: publish.sh violates the publish command policy');
        }
      },
    },
    {
      name: 'mutation-publish-command-policy-caught',
      description: 'the policy check detects the publish directory being redirected away from the member',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const source = await repo.read(PUBLISH_SH);
        if (!commandPolicyHolds(source)) {
          throw new Error('publish-command-policy: policy already broken before sabotage');
        }
        await repo.write(PUBLISH_SH, source.replace('cd "${root_dir}/packages/diene_dart_lib"', 'cd "${root_dir}"'));
        if (commandPolicyHolds(await repo.read(PUBLISH_SH))) {
          throw new Error('publish-command-policy: policy survived sabotage');
        }
      },
    },
  ],
};
