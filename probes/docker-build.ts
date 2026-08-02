import { expectGreen } from './lib/helpers.ts';

// `reports/` is both git-ignored and docker-ignored, so the exported archive never
// re-enters the build context and never shows up as sandbox state.
const artifacts = 'reports/docker-oci';
const archive = `${artifacts}/diene-go-base.oci.tar`;
const platforms = 'linux/arm64,linux/amd64';
const published = ['amd64', 'arm64'];

// The leading removal is what makes the assertion mean something: a stale archive from an
// earlier run must never be the thing skopeo reads.
const build = [
  `rm -rf ${artifacts}`,
  `mkdir -p ${artifacts}`,
  `CI_DOCKER_CONTEXT=. CI_DOCKER_IMAGE=diene-go-base CI_DOCKERFILE=infra/Dockerfile CI_DOCKER_OUTPUT=${archive} CI_DOCKER_PLATFORM=${platforms} CI_DOCKER_PUSH=false nix develop .#cd -c ./scripts/ci/docker.sh`,
].join(' && ');

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-docker-build-green',
      description: 'The workspace Docker script builds the unprivileged Go image for every published architecture.',
      kind: 'baseline',
      async run(repo: any) {
        try {
          await expectGreen(repo, build, 'docker-build', 1800000);
          // An exit code only proves buildx ran; the index has to name both architectures CI publishes.
          const inspected = await repo.exec(`nix develop .#cd -c skopeo inspect --raw oci-archive:${archive}`, {
            timeoutMs: 240000,
          });
          if (inspected.exitCode !== 0) {
            throw new Error(`docker-build left no readable OCI index: ${inspected.stderr || inspected.stdout}`);
          }
          // A single-architecture export carries no `manifests` list at all, so treat that as zero architectures
          // rather than letting it crash on a property read.
          const architectures = (JSON.parse(inspected.stdout).manifests ?? []).map(
            (entry: any) => entry.platform?.architecture,
          );
          const missing = published.filter(architecture => !architectures.includes(architecture));
          if (missing.length > 0) {
            throw new Error(
              `the exported OCI index omits ${missing.join(', ')}; it declares ${architectures.join(', ') || 'none'}`,
            );
          }
        } finally {
          await repo.exec(`rm -rf ${artifacts}`);
        }
      },
    },
  ],
};
