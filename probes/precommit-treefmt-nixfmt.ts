import type { ProbeDefinition } from "@cyanprint/contracts";

const gate =
  "nix develop --no-write-lock-file .#default -c pre-commit run treefmt --all-files";

const definition: ProbeDefinition = {
  contractVersion: 1,
  sandbox: { snapshot: "git" },
  probes: [
    {
      name: "treefmt-nixfmt-baseline-green",
      description:
        "The generated treefmt hook passes nixfmt on the healthy root sample.",
      kind: "baseline",
      timeoutMs: 240000,
      async run(repo) {
        const result = await repo.exec(gate, { timeoutMs: 240000 });
        if (result.exitCode !== 0) {
          throw new Error(
            `treefmt nixfmt baseline failed: ${result.stderr || result.stdout}`,
          );
        }
      },
    },
    {
      name: "nixfmt-violation-reddens-treefmt-hook",
      description:
        "A structural Nix formatting violation must turn the nixfmt member red.",
      kind: "mutation",
      timeoutMs: 240000,
      async run(repo) {
        await repo.patch("nix/packages.nix", {
          find: "all = rec {",
          replace: "all=rec{",
        });
        const result = await repo.exec(gate, { timeoutMs: 240000 });
        if (result.exitCode === 0) {
          throw new Error(
            "treefmt nixfmt stayed green after a Nix formatting violation",
          );
        }
      },
    },
  ],
};

export default definition;
