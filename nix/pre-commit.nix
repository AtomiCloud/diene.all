{
  packages,
  formatter,
  pkgs,
  pre-commit-lib,
}:
let
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

    # ### dotnet-base-hooks
    # #### source: dotnet-base
    dotnetlint = {
      enable = true;
      name = ".NET lint";
      entry = "${dotnetlint-precommit}/bin/dotnetlint-precommit";
      files = "^(.*\\.cs|.*\\.csproj|Directory\\.Build\\.props|Directory\\.Packages\\.props|dotnet-base\\.slnx|global\\.json)$";
      pass_filenames = false;
      language = "system";
    };

    a-dotnet-release-types = {
      enable = true;
      name = ".NET release type vocabulary";
      entry = validator "scripts/validate/dotnet-release.sh";
      files = "^(atomi_release\\.yaml|\\.gitlint)$";
      pass_filenames = false;
      language = "system";
    };

    gitlint = {
      enable = true;
      name = "Git commit message lint";
      entry = "${packages.gitlint}/bin/gitlint --staged --msg-filename";
      stages = [ "commit-msg" ];
      pass_filenames = true;
      language = "system";
    };

    # ### shared-hooks
    # #### source: shared
    a-claude-links = {
      enable = true;
      name = "CLAUDE link integrity";
      entry = "${pkgs.coreutils}/bin/env SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt ${pkgs.lychee}/bin/lychee --offline --no-progress CLAUDE.md";
      files = "^(CLAUDE\\.md|docs/standards/.*\\.md)$";
      pass_filenames = false;
      language = "system";
    };

    a-markdownlint = {
      enable = true;
      name = "Markdown lint";
      entry = "${pkgs.markdownlint-cli2}/bin/markdownlint-cli2";
      files = "^(CLAUDE\\.md|README\\.md|docs/standards/(authorization|contracts|contributor-docs|datetime|domain-driven-design|functional-practices|software-design-philosophy|solid-principles|stateless-oop-di|testing|three-layer-architecture|utilities|validation)/.*\\.md|\\.claude/skills/(authorization|contributor-docs|datetime|domain-driven-design|functional-practices|software-design-philosophy|solid-principles|stateless-oop-di|testing|three-layer-architecture|utilities|validation)/SKILL\\.md)$";
      pass_filenames = true;
      language = "system";
    };
  };
}
