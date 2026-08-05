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
  # G7, justified rather than reduced: the four are a 2x2 over (tool) x (test
  # reachability), not four spellings of one check, and each axis catches a class the
  # other cannot see.
  #   deadcode -test ./...      vs  deadcode ./...       (-test counts tests as callers)
  #   staticcheck -tests=true   vs  staticcheck -tests=false
  # Dropping the production pass loses production code kept alive ONLY by its own test,
  # which is dead in the shipped binary and invisible to the whole pass. Dropping the
  # whole pass loses defects inside test files, which the production pass never loads.
  # The nonblocking lax feed is a report, not a gate, so it stays out of this entry.
  #
  # G3: the vendored-GOPROXY plumbing below stays in this template. The registry
  # (v3.14.0) ships the go BINARIES - deadcode, go-validator, dlint - but not this
  # machinery, and `go-deps` cannot move as-is: it is `buildGoModule` over `src = ../.`
  # with this repo's own vendorHash, so it is parameterised on this module graph rather
  # than shared. Left whole rather than half-moved.
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
    # atomiutils supplies bash/jq/yq plus the coreutils/find/grep/sed binaries the
    # validators call - and, since registry v3.12.0, rg as well - so declaring any
    # of those separately would duplicate the bundle and collide with it in this
    # buildEnv. That is not a prediction: while v3.12.0 was landing, a standalone
    # nixpkgs ripgrep alongside the bundle failed this very buildEnv with
    # "conflicting subpath ... /bin/rg". git is the only entry left that the
    # bundle does not already carry.
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

  dlint = check: "${packages.dlint}/bin/dlint ${check}";
  dlints =
    checks:
    "${packages.atomiutils}/bin/bash -c '${
      builtins.concatStringsSep " && " (map (check: "${packages.dlint}/bin/dlint ${check}") checks)
    }'";
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
      entry = dlints [
        "action-pins trusted"
        "action-pins non-trusted"
      ];
      files = "^(\\.github/workflows/.*\\.ya?ml|config/action-trust\\.json)$";
      pass_filenames = false;
      language = "system";
    };

    a-enforce-exec = {
      enable = true;
      name = "Executable shell scripts";
      entry = dlint "exec-bits";
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
      entry = "${packages.infisical}/bin/infisical scan . -v --redact";
      pass_filenames = false;
      language = "system";
    };

    a-infisical-staged = {
      enable = true;
      name = "Staged secrets scan";
      entry = "${packages.infisical}/bin/infisical scan git-changes --staged -v --redact";
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

    a-releaser-commit = {
      enable = true;
      name = "Conventional commit";
      entry = "${packages.releaser}/bin/releaser lint-commit -c atomi_release.yaml";
      stages = [ "commit-msg" ];
      pass_filenames = true;
      language = "system";
    };

    # Source following belongs to the gate itself, not to an ambient SHELLCHECK_OPTS:
    # pre-commit partitions the staged files, so a script and the script it sources
    # routinely land in different batches, and bare ShellCheck then raises SC1091 on
    # healthy sources. `-x` follows a declared `source=`, and `--source-path=SCRIPTDIR`
    # adds the checked script's own directory so script-relative directives resolve
    # too, on top of the repository-root-relative ones the working directory already
    # covers. Findings from the sourced file stay out of the report (that would need
    # `-a`), so the gate gains resolution without gaining noise.
    a-shellcheck = {
      enable = true;
      name = "Shellcheck";
      entry = "${packages.shellcheck}/bin/shellcheck -x --source-path=SCRIPTDIR";
      files = ".*\\.sh$";
      pass_filenames = true;
      language = "system";
    };

    a-skills-freshness = {
      enable = true;
      name = "Vendored skills freshness";
      entry = dlint "skills-fresh";
      pass_filenames = false;
      language = "system";
    };

    a-workflows = {
      enable = true;
      name = "Workflow wiring and release policy";
      entry = "${packages.atomiutils}/bin/bash -c '${packages.dlint}/bin/dlint ci-wiring && ( export PATH=${validator-runtime}/bin; ${packages.atomiutils}/bin/bash scripts/validate/workflows.sh release-trigger && ${packages.atomiutils}/bin/bash scripts/validate/workflows.sh release-concurrency )'";
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
