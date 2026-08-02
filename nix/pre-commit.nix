{
  packages,
  formatter,
  pkgs,
  pre-commit-lib,
}:
let
  validator-runtime = pkgs.buildEnv {
    name = "workspace-validator-runtime";
    # atomiutils supplies bash/jq/yq plus the coreutils/find/grep/sed binaries the
    # validators call, so declaring those separately would duplicate the bundle
    # (and collide with it in this buildEnv). git, ripgrep, and util-linux (for
    # flock) do not overlap it.
    paths = [
      packages.atomiutils
      packages.git
      packages.ripgrep
      pkgs.util-linux
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
  dotnetlint-dependencies =
    (pkgs.buildDotnetModule {
      pname = "dotnet-base-dependencies";
      version = "0";
      src = ../.;
      projectFile = "dotnet-base.slnx";
      nugetDeps = ./dotnet-deps.json;
      dotnet-sdk = packages.dotnet-sdk_10;
    }).nugetDeps;
  dotnetlint-nuget-packages = pkgs.buildEnv {
    name = "dotnetlint-nuget-packages";
    paths = dotnetlint-dependencies;
    pathsToLink = [ "/share/nuget/packages" ];
  };
  dotnetlint-empty-source = pkgs.runCommand "dotnetlint-empty-nuget-source" { } ''
    mkdir -p "$out"
  '';
  # Upstream dotnetlint executes its source script with /usr/bin/env, which is
  # unavailable in pure Nix builds. Preserve that script while patching its
  # shebang until the package does so itself.
  dotnetlint-pure = pkgs.runCommand "dotnetlint-pure" { } ''
    mkdir -p "$out/bin" "$out/libexec"
    wrapper=${packages.dotnetlint}/bin/dotnetlint
    script=$(awk 'NF { line = $0 } END { print line }' "$wrapper")
    cp "$script" "$out/libexec/dotnetlint"
    patchShebangs "$out/libexec/dotnetlint"
    substitute "$wrapper" "$out/bin/dotnetlint" \
      --replace-fail "$script" "$out/libexec/dotnetlint"
    chmod +x "$out/bin/dotnetlint"
  '';
  dotnetlint-precommit = pkgs.writeShellApplication {
    name = "dotnetlint-precommit";
    runtimeInputs = [
      packages.dotnet-sdk_10
      dotnetlint-pure
    ];
    text = ''
      dotnet restore dotnet-base.slnx \
        --no-cache \
        --packages ${dotnetlint-nuget-packages}/share/nuget/packages \
        --source ${dotnetlint-empty-source} \
        -p:NuGetAudit=false \
        >/dev/null
      exec dotnetlint
    '';
  };
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
      files = "^(CLAUDE\\.md|README\\.md|docs/standards/.*\\.md|\\.claude/skills/[^/]+/SKILL\\.md)$";
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
      entry = "${packages.releaser}/bin/releaser lint-commit -c atomi_release.yaml";
      stages = [ "commit-msg" ];
      pass_filenames = true;
      language = "system";
    };

    a-shellcheck = {
      enable = true;
      name = "Shellcheck";
      # Follow explicit `# shellcheck source=...` declarations so the result is
      # independent of how pre-commit chunks the filename list.
      entry = "${packages.shellcheck}/bin/shellcheck -x";
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
    dotnetlint = {
      enable = true;
      name = ".NET lint";
      entry = "${dotnetlint-precommit}/bin/dotnetlint-precommit";
      files = "^(.*\\.cs|.*\\.csproj|Directory\\.Build\\.props|Directory\\.Packages\\.props|dotnet-base\\.slnx|global\\.json)$";
      pass_filenames = false;
      language = "system";
    };

  };
}
