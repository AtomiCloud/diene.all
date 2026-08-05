{
  packages,
  formatter,
  pkgs,
  pre-commit-lib,
}:
let
  go-deps = pkgs.buildGoModule {
    pname = "diene-go-base-dependencies";
    version = "0";
    src = ../.;
    vendorHash = "sha256-NbeafHrobDMronPIB3abd5J/8dPfNtGNuQsI6vcj820=";
    proxyVendor = true;
  };
  go-lint-runtime = pkgs.buildEnv {
    name = "go-base-lint-runtime";
    paths = [
      pkgs.bash
      packages.git
      packages.go
      packages.golangci-lint
      pkgs.coreutils
    ];
  };
  go-lint = "${pkgs.bash}/bin/bash -c 'export PATH=${go-lint-runtime}/bin; export CGO_ENABLED=0; export GOPROXY=file://${go-deps.goModules}; export GOSUMDB=off; export GOMODCACHE=\"\${TMPDIR:-/tmp}/go-base-mod-cache\"; exec ${packages.golangci-lint}/bin/golangci-lint run --timeout 5m ./...'";
  # Every strict component loads all packages, so they need the lint hook's vendored proxy; jq counts the JSON findings.
  go-deadcode-runtime = pkgs.buildEnv {
    name = "go-base-deadcode-runtime";
    paths = [
      pkgs.bash
      packages.deadcode
      packages.git
      packages.go
      packages.staticcheck
      pkgs.coreutils
      pkgs.jq
    ];
  };
  # The four strict components in CI's order, stopping at the first non-zero exit; the nonblocking lax feed stays out.
  go-deadcode = "${pkgs.bash}/bin/bash -c 'export PATH=${go-deadcode-runtime}/bin; export CGO_ENABLED=0; export GOPROXY=file://${go-deps.goModules}; export GOSUMDB=off; export GOMODCACHE=\"\${TMPDIR:-/tmp}/go-base-mod-cache\"; ${
    builtins.concatStringsSep " && " (
      map (component: "${pkgs.bash}/bin/bash ./scripts/local/${component}.sh") [
        "staticcheck-whole"
        "deadcode-whole"
        "staticcheck-production"
        "deadcode-production"
      ]
    )
  }'";
  validator-runtime = pkgs.buildEnv {
    name = "workspace-validator-runtime";
    # atomiutils bundles the shell, coreutils, find, grep, sed, jq, yq, rg and
    # flock the validators call; declaring any of those separately collides here.
    paths = [
      packages.atomiutils
      packages.git
    ];
  };
  validator =
    command:
    "${packages.atomiutils}/bin/bash -c 'export PATH=${validator-runtime}/bin; exec ${packages.atomiutils}/bin/bash ${command}'";
  # One hook, several invocations of the same validator: identical runtime PATH,
  # stopping at the first non-zero exit so the reported failure is the gate that
  # actually failed. Used where one validator script owns several modes and the
  # modes do not warrant separate hooks.
  validators =
    commands:
    "${packages.atomiutils}/bin/bash -c 'export PATH=${validator-runtime}/bin; ${
      builtins.concatStringsSep " && " (
        map (command: "${packages.atomiutils}/bin/bash ${command}") commands
      )
    }'";

  # Give skills freshness the ambient Go cache so partial isolated caches cannot decide the result.
  go-ambient-validator-runtime = pkgs.buildEnv {
    name = "go-base-ambient-validator-runtime";
    paths = [
      validator-runtime
      packages.go
    ];
  };
  go-ambient-validator =
    command:
    "${packages.atomiutils}/bin/bash -c 'export PATH=${go-ambient-validator-runtime}/bin; exec ${packages.atomiutils}/bin/bash ${command}'";
in
pre-commit-lib.run {
  src = ../.;

  hooks = {
    treefmt = {
      enable = true;
      package = formatter;
      excludes = [
        "^\\.claude/skills/vendor/"
        "^Changelog\\.md$"
        "^docs/developer/CommitConventions\\.md$"
        "^infra/root_chart/"
      ];
    };

    a-action-pins = {
      enable = true;
      name = "Action pins";
      entry = validators [
        "scripts/validate/action-pins.sh trusted"
        "scripts/validate/action-pins.sh non-trusted"
      ];
      files = "^\\.github/workflows/.*\\.ya?ml$";
      pass_filenames = false;
      language = "system";
    };

    # always_run, not a files pattern: the check reads CLAUDE.md but fails on the
    # state of its *targets*, and a deleted or renamed target need not touch any
    # path a pattern could name. Selecting on content would make deletion coverage
    # depend on the deleter also editing a watched file. The check is offline and
    # costs milliseconds, so running it every time is cheaper than the gap.
    # SSL_CERT_FILE is bound explicitly because the pure flake derivation has no
    # ambient certificate file, and lychee refuses to start without one even under
    # --offline.
    a-claude-links = {
      enable = true;
      name = "CLAUDE link integrity";
      entry = "${pkgs.coreutils}/bin/env SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt ${pkgs.lychee}/bin/lychee --offline --no-progress CLAUDE.md";
      always_run = true;
      pass_filenames = false;
      language = "system";
    };

    # The contributor-doc workflow is an executable state contract, not prose-only
    # guidance. This assert-the-asserter checks its mirrored schemas and step sets,
    # then drives healthy and destructive transition fixtures on every commit.
    a-contributor-docs-contract = {
      enable = true;
      name = "Contributor-doc state contract";
      entry = validator "docs/standards/contributor-docs/scripts/init-state.sh --check-write-contract";
      always_run = true;
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

    a-helm-lint = {
      enable = true;
      name = "Helm lint";
      entry = "${packages.infrautils}/bin/helm lint infra/root_chart";
      files = "^infra/root_chart/.*";
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

    # The selector is directory-shaped on purpose: every standard under
    # docs/standards/ and every first-level skill trigger is linted, so adding a
    # topic needs no edit here. Vendored skills sit deeper than one level and are
    # ignored again by .markdownlint-cli2.jsonc.
    a-markdownlint = {
      enable = true;
      name = "Markdown lint";
      entry = "${pkgs.markdownlint-cli2}/bin/markdownlint-cli2";
      files = "^(CLAUDE\\.md|README\\.md|docs/developer/go-baseline\\.md|docs/standards/.*\\.md|\\.claude/skills/[^/]+/SKILL\\.md)$";
      pass_filenames = true;
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
      name = "Release config schema and types";
      entry = validator "scripts/validate/release-config.sh all";
      files = "^atomi_release\\.yaml$";
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
      # Follow sourced scripts when pre-commit splits a large filename set across invocations.
      entry = "${packages.shellcheck}/bin/shellcheck -x";
      files = ".*\\.sh$";
      pass_filenames = true;
      language = "system";
    };

    a-skills-freshness = {
      enable = true;
      name = "Vendored skills freshness";
      entry = go-ambient-validator "scripts/validate/skills-freshness.sh";
      pass_filenames = false;
      language = "system";
    };

    # The wiring mode keeps both of its halves — every referenced scripts/ci entry
    # point exists and is executable, and every orchestrator job resolves to a
    # repository-local reusable workflow that calls one — unchanged.
    a-workflows = {
      enable = true;
      name = "Workflow wiring, release trigger and concurrency";
      entry = validators [
        "scripts/validate/workflows.sh wiring"
        "scripts/validate/workflows.sh release-trigger"
        "scripts/validate/workflows.sh release-concurrency"
      ];
      files = "^\\.github/workflows/.*\\.ya?ml$";
      pass_filenames = false;
      language = "system";
    };

    # Blocking like the CI deadcode job: the four strict components share one hook, and the hook itself is a proven mechanism.
    a-deadcode = {
      enable = true;
      name = "Go deadcode strict passes";
      entry = go-deadcode;
      files = "(^|/).*\\.go$|^go\\.(mod|sum)$";
      pass_filenames = false;
      language = "system";
    };

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
  };
}
