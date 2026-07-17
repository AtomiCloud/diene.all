import type { ProbeDefinition } from "@cyanprint/contracts";

const definition: ProbeDefinition = {
  contractVersion: 1,
  sandbox: { snapshot: "git" },
  probes: [
    {
      name: "default-dev-shell-loads",
      description:
        "The default Nix development shell loads and executes a real command.",
      kind: "baseline",
      timeoutMs: 240000,
      async run(repo) {
        const result = await repo.exec(
          "nix develop --no-write-lock-file .#default -c true",
          { timeoutMs: 240000 },
        );
        if (result.exitCode !== 0) {
          throw new Error(
            `default dev shell failed to load: ${result.stderr || result.stdout}`,
          );
        }
      },
    },
  ],
};

export default definition;
