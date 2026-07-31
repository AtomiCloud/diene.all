# Diene workspace baseline

<!-- ### nix-root -->
<!-- #### source: main -->

Diene's reproducible development environment is managed by Nix. Run `direnv allow` once, then use `pls` tasks from the loaded shell.

<!-- ### workspace -->
<!-- #### source: workspace -->

This branch is the workspace baseline inherited by every downstream sample: split CI/CD, Helm, secrets, release configuration, validators, standards, and vendored agent-skill synchronization.

## Commands

- `pls setup` — synchronize installed diene package skills.
- `pls lint` — run every pre-commit gate.
- `pls helm:lint` / `pls helm:template` — validate or render the root chart.
- `pls secret:scan` — scan tracked content for secrets.
- `pls skills:sync` — rebuild `.claude/skills/vendor/` from installed packages.

## Fleet system proof

The required full fleet proof runs the driver on one anonymous, cold-created
Namespace VM and uses only that instance's built-in single-node k3s:

```sh
nix develop .#ci -c ./scripts/ci/fleet-sit-proof.sh --full
```

Full mode creates exactly `--ephemeral --duration 2h --machine_type 16x32
--enable=kubernetes:1.33 --wait_kube_system`. The two-hour TTL is a cost
backstop, not cleanup. The observed Namespace id contract is exactly 13
lowercase alphanumeric characters. Harness creation retains the exact cidfile,
minimal `--output json` stdout, stderr, and a separate full metadata receipt
written by `--output_json_to`; every success, failure, or signal attempts `nsc
destroy <exact-instance-id> --force` and independently proves that exact id
absent. Preserve `sit-report/` after the run; `sit-report.json` is the inner
L0-L9 result and `lifecycle/lifecycle.json` binds the source snapshot, each
create artifact, transfer and toolchain evidence, report digest, timings,
destroy, and absence.

For the cheap local source gate, with no Namespace create/use/destroy:

```sh
nix develop .#ci -c ./scripts/ci/fleet-sit-proof.sh --prepare-only
```

A ratchet lead may register a pre-created instance before first SSH by setting
both `FLEET_SIT_NSC_INSTANCE_ID` and the absolute
`FLEET_SIT_NSC_CREATE_RECEIPT` path. That receipt must be the full instance
metadata file produced by `nsc create --output_json_to /absolute/path`; the
minimal JSON written to stdout by `--output json` is not sufficient. The
wrapper revalidates its exact id, labels, 16x32 shape, Kubernetes receipt,
hostname, Wolfi/k3s topology, and still owns exact-id destruction. Cleanup
ownership begins before source and nsc-client preflight once the full invocation
accepts an empty evidence directory and the exact 13-character provided id. See
[the fleet repository contract](docs/domain/fleet-repo.md#testing-and-proof-tiers).

## Standards

- [CI/CD workflows](docs/standards/ci-cd/index.md)
- [conventional commits](docs/standards/conventional-commits/index.md)
- [Helm charts and publishing](docs/standards/helm/index.md)
- [Infisical and secrets](docs/standards/infisical/index.md)
- [linting and pre-commit](docs/standards/linting/index.md)
- [Nix flakes and development shells](docs/standards/nix/index.md)
- [release automation](docs/standards/semantic-release/index.md)
- [service-tree identity](docs/standards/service-tree/index.md)
- [shell scripts](docs/standards/shell-scripts/index.md)
- [Taskfile conventions](docs/standards/taskfile/index.md)

<!-- ### shared -->
<!-- #### source: shared -->

## Shared standards

- [Authorization](docs/standards/authorization/index.md)
- [Contributor documentation](docs/standards/contributor-docs/index.md)
- [Date and time](docs/standards/datetime/index.md)
- [Domain-driven design](docs/standards/domain-driven-design/index.md)
- [Functional practices](docs/standards/functional-practices/index.md)
- [Software design philosophy](docs/standards/software-design-philosophy/index.md)
- [SOLID principles](docs/standards/solid-principles/index.md)
- [Stateless OOP and dependency injection](docs/standards/stateless-oop-di/index.md)
- [Testing](docs/standards/testing/index.md)
- [Three-layer architecture](docs/standards/three-layer-architecture/index.md)
- [Utility libraries](docs/standards/utilities/index.md)
- [Data validation](docs/standards/validation/index.md)

Domain-specific documentation belongs under [docs/domain/](docs/domain/README.md).
The `docs/standards/contracts/` location is reserved for the separately owned C0
contracts standard.

<!-- ### helm-wrapper -->
<!-- #### source: helm-wrapper -->

## Helm wrapper sample

This branch adds the production-grade wrapper chart, stacked values, generated schema, rendered-manifest validation, k3d proof, and dual publish modes.

- `pls build` — vendor external config and build pinned chart dependencies.
- `pls test:unit` — run schema, lint, render, contracts, VAP, and publish dry-runs.
- `pls test:int` — install on ephemeral k3d and round-trip the chart through a local OCI registry.
- `pls example:lapras:template` — render the independent landscape + cluster stack.
- [Helm wrapper baseline](docs/developer/helm-wrapper-baseline.md)
