{
  packages,
  formatter,
  pkgs,
  pre-commit-lib,
}:
let
  go-deps = pkgs.buildGoModule {
    pname = "diene-go-consumer-dependencies";
    version = "0";
    src = ../.;
    vendorHash = "sha256-sC4fXO4G3Pfl8rzj1CpIeFouMTApYF1ek9aZ09Rxzm4=";
    proxyVendor = true;
  };
  go-lint-runtime = pkgs.buildEnv {
    name = "go-consumer-lint-runtime";
    paths = [
      packages.bash
      packages.git
      packages.go
      packages.golangci-lint
      pkgs.coreutils
    ];
  };
  go-lint = "${packages.bash}/bin/bash -c 'export PATH=${go-lint-runtime}/bin; export CGO_ENABLED=0; export GOPROXY=file://${go-deps.goModules}; export GOSUMDB=off; export GOMODCACHE=\"\${TMPDIR:-/tmp}/go-consumer-mod-cache\"; exec ${packages.golangci-lint}/bin/golangci-lint run --timeout 5m ./...'";
  validator-runtime = pkgs.buildEnv {
    name = "workspace-validator-runtime";
    paths = [
      packages.bash
      packages.git
      packages.jq
      packages.ripgrep
      packages.yq-go
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.gnused
    ];
  };
  validator =
    command:
    "${packages.bash}/bin/bash -c 'export PATH=${validator-runtime}/bin; exec ${packages.bash}/bin/bash ${command}'";
in
pre-commit-lib.run {
  src = ../.;

  # ### nix-root-format
  # #### source: main
  hooks = {
    treefmt = {
      enable = true;
      package = formatter;
      excludes = [
        "^\\.claude/skills/vendor/"
        "^Changelog\\.md$"
        "^docs/developer/CommitConventions\\.md$"
        "^infra/root_chart/"

        # ### go-consumer-treefmt-excludes
        # #### source: go-consumer
        "^infra/primordial_chart/"
        "^schemas/"
      ];
    };

    # ### workspace-hooks
    # #### source: workspace
    a-action-pins-non-trusted = {
      enable = true;
      name = "Non-trusted action SHA pins";
      entry = validator "scripts/validate/action-pins.sh non-trusted";
      files = "^\\.github/workflows/.*\\.ya?ml$";
      pass_filenames = false;
      language = "system";
    };

    a-action-pins-trusted = {
      enable = true;
      name = "Trusted action major pins";
      entry = validator "scripts/validate/action-pins.sh trusted";
      files = "^\\.github/workflows/.*\\.ya?ml$";
      pass_filenames = false;
      language = "system";
    };

    a-cache-tags = {
      enable = true;
      name = "nscloud cache-tag shape";
      entry = validator "scripts/validate/cache-tags.sh";
      files = "^\\.github/workflows/.*\\.ya?ml$";
      pass_filenames = false;
      language = "system";
    };

    a-enforce-exec = {
      enable = true;
      name = "Executable shell scripts";
      entry = validator "scripts/validate/executable-shells.sh";
      files = ".*\\.sh$";
      pass_filenames = false;
      language = "system";
    };

    a-helm-docs = {
      enable = true;
      name = "Helm docs";
      entry = "${packages.infralint}/bin/helm-docs --chart-search-root infra/root_chart";
      files = "^infra/root_chart/.*";
      pass_filenames = false;
      language = "system";
    };

    a-helm-lint = {
      enable = true;
      name = "Helm lint";
      entry = "${packages.kubernetes-helm}/bin/helm lint infra/root_chart";
      files = "^infra/root_chart/.*";
      pass_filenames = false;
      language = "system";
    };

    # ### go-consumer-primordial-chart-hooks
    # #### source: go-consumer
    a-helm-docs-primordial = {
      enable = true;
      name = "Primordial Helm docs";
      entry = "${packages.infralint}/bin/helm-docs --chart-search-root infra/primordial_chart";
      files = "^infra/primordial_chart/.*";
      pass_filenames = false;
      language = "system";
    };

    a-helm-lint-primordial = {
      enable = true;
      name = "Primordial Helm lint";
      entry = "${packages.kubernetes-helm}/bin/helm lint infra/primordial_chart";
      files = "^infra/primordial_chart/.*";
      pass_filenames = false;
      language = "system";
    };

    a-infisical = {
      enable = true;
      name = "Secrets scan";
      entry = "${packages.infisical}/bin/infisical scan . -v";
      pass_filenames = false;
      language = "system";
    };

    a-infisical-staged = {
      enable = true;
      name = "Staged secrets scan";
      entry = "${packages.infisical}/bin/infisical scan git-changes --staged -v";
      pass_filenames = false;
      language = "system";
    };

    a-many-owner = {
      enable = true;
      name = "Many-owner keyed blocks";
      entry = validator "scripts/validate/many-owner.sh";
      pass_filenames = false;
      language = "system";
    };

    a-nixpkgs-pin = {
      enable = true;
      name = "Shared nixpkgs pin";
      entry = validator "scripts/validate/nixpkgs-pin.sh";
      files = "^(flake\\.nix|flake\\.lock|nix/.*|nix/snapshots/nixpkgs\\.json)$";
      pass_filenames = false;
      language = "system";
    };

    a-release-config = {
      enable = true;
      name = "Release config schema";
      entry = validator "scripts/validate/release-config.sh schema";
      files = "^atomi_release\\.yaml$";
      pass_filenames = false;
      language = "system";
    };

    a-release-types = {
      enable = true;
      name = "Release type vocabulary";
      entry = validator "scripts/validate/release-config.sh types";
      files = "^atomi_release\\.yaml$";
      pass_filenames = false;
      language = "system";
    };

    a-release-trigger = {
      enable = true;
      name = "Release workflow trigger";
      entry = validator "scripts/validate/workflows.sh release-trigger";
      files = "^\\.github/workflows/.*\\.ya?ml$";
      pass_filenames = false;
      language = "system";
    };

    a-release-concurrency = {
      enable = true;
      name = "Release workflow concurrency";
      entry = validator "scripts/validate/workflows.sh release-concurrency";
      files = "^\\.github/workflows/.*\\.ya?ml$";
      pass_filenames = false;
      language = "system";
    };

    a-workflow-names = {
      enable = true;
      name = "CI/CD workflow names";
      entry = validator "scripts/validate/workflows.sh workflow-names";
      files = "^\\.github/workflows/.*\\.ya?ml$";
      pass_filenames = false;
      language = "system";
    };

    a-releaser-commit = {
      enable = true;
      name = "Conventional commit";
      entry = "releaser lint-commit -c atomi_release.yaml";
      stages = [ "commit-msg" ];
      pass_filenames = true;
      language = "system";
    };

    a-shellcheck = {
      enable = true;
      name = "Shellcheck";
      entry = "${packages.shellcheck}/bin/shellcheck";
      files = ".*\\.sh$";
      pass_filenames = true;
      language = "system";
    };

    a-skills-freshness = {
      enable = true;
      name = "Vendored skills freshness";
      entry = validator "scripts/validate/skills-freshness.sh";
      pass_filenames = false;
      language = "system";
    };

    a-workflow-wiring = {
      enable = true;
      name = "Workflow job-to-script wiring";
      entry = validator "scripts/validate/workflows.sh wiring";
      files = "^\\.github/workflows/.*\\.ya?ml$";
      pass_filenames = false;
      language = "system";
    };

    # ### go-base-hooks
    # #### source: go-base
    a-go-black-box = {
      enable = true;
      name = "Go black-box tests";
      entry = validator "scripts/validate/go-black-box-tests.sh";
      files = "(^|/).*(_test|export_test)\\.go$";
      pass_filenames = false;
      language = "system";
    };

    a-golangci-lint = {
      enable = true;
      name = "golangci-lint";
      entry = go-lint;
      files = "(^|/).*\\.go$|^go\\.(mod|sum)$|^\\.golangci\\.yaml$";
      pass_filenames = false;
      language = "system";
    };

    # ### go-consumer-hooks
    # #### source: go-consumer
    a-constants-sync = {
      enable = true;
      name = "Keyed adapter constants sync";
      entry = validator "scripts/validate/constants-sync.sh";
      files = "^(config/settings\\.yaml|lib/appconfig/constants\\.go)$";
      pass_filenames = false;
      language = "system";
    };

    a-rebrand-config = {
      enable = true;
      name = "Config-driven rebrand guard";
      entry = validator "scripts/validate/rebrand.sh";
      files = "^(config/settings\\.yaml|cmd/.*\\.go|lib/.*\\.go|adapters/.*\\.go)$";
      pass_filenames = false;
      language = "system";
    };

    a-schema-drift = {
      enable = true;
      name = "Generated config schema drift";
      entry = validator "scripts/validate/schema-drift.sh";
      files = "^(config/.*\\.yaml|schemas/.*\\.json|lib/appconfig/.*\\.go)$";
      pass_filenames = false;
      language = "system";
    };

    # ### shared-hooks
    # #### source: shared
    a-claude-links = {
      enable = true;
      name = "CLAUDE link integrity";
      entry = "${pkgs.coreutils}/bin/env SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt ${pkgs.lychee}/bin/lychee --offline --no-progress CLAUDE.md";
      files = "^(CLAUDE\\.md|docs/developer/(go-baseline|go-consumer)\\.md|docs/standards/.*\\.md)$";
      pass_filenames = false;
      language = "system";
    };

    a-markdownlint = {
      enable = true;
      name = "Markdown lint";
      entry = "${pkgs.markdownlint-cli2}/bin/markdownlint-cli2";
      files = "^(CLAUDE\\.md|README\\.md|docs/developer/(go-baseline|go-consumer)\\.md|docs/standards/(authorization|contracts|contributor-docs|datetime|domain-driven-design|functional-practices|grafana-dashboards|observability|software-design-philosophy|solid-principles|stateless-oop-di|testing|three-layer-architecture|utilities|validation)/.*\\.md|infra/primordial_chart/.*\\.md|observability/.*\\.md|probes/observability-.*\\.md|\\.claude/skills/(authorization|contributor-docs|datetime|domain-driven-design|functional-practices|go-baseline|software-design-philosophy|solid-principles|stateless-oop-di|testing|three-layer-architecture|utilities|validation)/SKILL\\.md|\\.claude/skills/(grafana-alert|grafana-alert-set|grafana-dashboards|grafana-runbook|observability-check)/.*\\.md)$";
      pass_filenames = true;
      language = "system";
    };
  };
}
