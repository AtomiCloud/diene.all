import type { ProbeDefinition } from "@cyanprint/contracts";

const gate =
  "nix develop --no-write-lock-file .#default -c pre-commit run treefmt --all-files";

const workflow = `name: Probe
on: push
jobs:
  probe:
    runs-on: ubuntu-latest
    steps:
      - name: Invalid expression context
        run: echo "\${{ unknown.value }}"
`;

const definition: ProbeDefinition = {
  contractVersion: 1,
  sandbox: { snapshot: "git" },
  probes: [
    {
      name: "treefmt-actionlint-baseline-green",
      description:
        "The generated treefmt hook passes actionlint on the healthy root sample.",
      kind: "baseline",
      timeoutMs: 240000,
      async run(repo) {
        const result = await repo.exec(gate, { timeoutMs: 240000 });
        if (result.exitCode !== 0) {
          throw new Error(
            `treefmt actionlint baseline failed: ${result.stderr || result.stdout}`,
          );
        }
      },
    },
    {
      name: "invalid-workflow-reddens-treefmt-actionlint",
      description:
        "A semantically invalid workflow expression must turn the actionlint member red.",
      kind: "mutation",
      expectedImpact: [
        "binary-smoke",
        "precommit-treefmt-nixfmt",
        "precommit-treefmt-prettier",
        "precommit-treefmt-shfmt",
      ],
      timeoutMs: 240000,
      async run(repo) {
        await repo.write(".github/workflows/probe-actionlint.yaml", workflow);
        const staged = await repo.exec(
          "git add .github/workflows/probe-actionlint.yaml",
        );
        if (staged.exitCode !== 0) {
          throw new Error(
            `failed to stage actionlint fixture: ${staged.stderr || staged.stdout}`,
          );
        }
        const result = await repo.exec(gate, { timeoutMs: 240000 });
        if (result.exitCode === 0) {
          throw new Error(
            "treefmt actionlint stayed green after an invalid workflow expression",
          );
        }
      },
    },
  ],
};

export default definition;
