import type { ProbeDefinition } from "@cyanprint/contracts";

const gate =
  "nix develop --no-write-lock-file .#default -c pre-commit run treefmt --all-files";

const shellFixture = `#!/usr/bin/env bash
if true;then
 echo probe
fi
`;

const definition: ProbeDefinition = {
  contractVersion: 1,
  sandbox: { snapshot: "git" },
  probes: [
    {
      name: "treefmt-shfmt-baseline-green",
      description:
        "The generated treefmt hook passes shfmt on the healthy root sample.",
      kind: "baseline",
      timeoutMs: 240000,
      async run(repo) {
        const result = await repo.exec(gate, { timeoutMs: 240000 });
        if (result.exitCode !== 0) {
          throw new Error(
            `treefmt shfmt baseline failed: ${result.stderr || result.stdout}`,
          );
        }
      },
    },
    {
      name: "shfmt-violation-reddens-treefmt-hook",
      description:
        "A valid but unformatted shell script must turn the shfmt member red.",
      kind: "mutation",
      timeoutMs: 240000,
      async run(repo) {
        await repo.write("probe-shfmt.sh", shellFixture);
        const staged = await repo.exec("git add probe-shfmt.sh");
        if (staged.exitCode !== 0) {
          throw new Error(
            `failed to stage shfmt fixture: ${staged.stderr || staged.stdout}`,
          );
        }
        const result = await repo.exec(gate, { timeoutMs: 240000 });
        if (result.exitCode === 0) {
          throw new Error(
            "treefmt shfmt stayed green after an unformatted shell script",
          );
        }
      },
    },
  ],
};

export default definition;
