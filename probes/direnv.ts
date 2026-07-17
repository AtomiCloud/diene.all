import type { ProbeDefinition } from "@cyanprint/contracts";

const definition: ProbeDefinition = {
  contractVersion: 1,
  sandbox: { snapshot: "git" },
  probes: [
    {
      name: "direnv-loads-repo-environment",
      description:
        "The committed .envrc loads the repository environment in an isolated direnv config.",
      kind: "baseline",
      timeoutMs: 240000,
      async run(repo) {
        const result = await repo.exec(
          'config="$(mktemp -d)" && DIRENV_CONFIG="$config" direnv allow . && DIRENV_CONFIG="$config" direnv exec . true',
          { timeoutMs: 240000 },
        );
        if (result.exitCode !== 0) {
          throw new Error(
            `direnv failed to load .envrc: ${result.stderr || result.stdout}`,
          );
        }
      },
    },
  ],
};

export default definition;
