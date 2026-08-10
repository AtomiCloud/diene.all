{
  packages,
  formatter,
  pkgs,
  pre-commit-lib,
  env,
}:
let
  # toolchain-smoke asserts the DECLARED env lists actually provide their binaries.
  envPath = pkgs.lib.makeBinPath (env.system ++ env.main ++ env.lint ++ env.dev);
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
  # (v5) ships the go BINARIES - deadcode, go-validator, dlint - but not this
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
      ];
    };

    a-dlint = {
      enable = true;
      name = "dlint";
      entry = "${packages.atomiutils}/bin/bash -c 'PATH=${envPath}:\$PATH ${packages.dlint}/bin/dlint lint'";
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
      entry = "${packages.releaser}/bin/releaser lint-commit -c release.yaml";
      stages = [ "commit-msg" ];
      pass_filenames = true;
      language = "system";
    };

    a-skills-sync = {
      enable = true;
      name = "Vendored skills";
      entry = "${packages.skills-sync}/bin/skills-sync sync --frozen";
      pass_filenames = false;
      language = "system";
    };

    # -x + SCRIPTDIR: staged-file batching splits scripts from their sources,
    # so ShellCheck must follow source= directives itself.
    a-shellcheck = {
      enable = true;
      name = "Shellcheck";
      entry = "${packages.shellcheck}/bin/shellcheck -x --source-path=SCRIPTDIR";
      files = ".*\\.sh$";
      pass_filenames = true;
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
