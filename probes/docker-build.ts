import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-docker-build-green',
      description: 'The .NET base Docker script builds the unprivileged stub image.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'CI_DOCKER_CONTEXT=. CI_DOCKER_IMAGE=diene-dotnet-base CI_DOCKERFILE=infra/Dockerfile CI_DOCKER_PUSH=false nix develop .#cd -c ./scripts/ci/docker.sh',
          'docker-build',
        );
      },
    },
  ],
};
