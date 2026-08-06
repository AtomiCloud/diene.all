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
  dotnetlint-project = pkgs.buildDotnetModule {
    pname = "dotnet-base-dependencies";
    version = "0";
    src = ../.;
    projectFile = "dotnet-base.slnx";
    # Generated, never hand-authored: `nix build .#pre-commit.fetch-deps` (exposed at
    # the bottom of this file) rewrites nix/dotnet-deps.json. It is a pinned NuGet
    # closure and it stays while nix builds dotnet - see docs/standards/nix/index.md.
    nugetDeps = ./dotnet-deps.json;
    dotnet-sdk = packages.dotnet-sdk_10;
  };
  dotnetlint-dependencies = dotnetlint-project.nugetDeps;
  dotnetlint-nuget-packages = pkgs.buildEnv {
    name = "dotnetlint-nuget-packages";
    paths = dotnetlint-dependencies;
    pathsToLink = [ "/share/nuget/packages" ];
  };
  dotnetlint-empty-source = pkgs.runCommand "dotnetlint-empty-nuget-source" { } ''
    mkdir -p "$out"
  '';
  # Patch dotnetlint's /usr/bin/env shebang for pure Nix builds.
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
(pre-commit-lib.run {
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
      files = "^(\\.github/workflows/.*\\.ya?ml|config/action-trust\\.json)$";
      pass_filenames = false;
      language = "system";
    };

    a-action-pins-trusted = {
      enable = true;
      name = "Trusted action major pins";
      entry = validator "scripts/validate/action-pins.sh trusted";
      files = "^(\\.github/workflows/.*\\.ya?ml|config/action-trust\\.json)$";
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
      entry = "${packages.kubernetes-helm}/bin/helm lint infra/root_chart";
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

    a-many-owner = {
      enable = true;
      name = "Many-owner keyed blocks";
      entry = validator "scripts/validate/many-owner.sh";
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

    a-releaser-commit = {
      enable = true;
      name = "Conventional commit";
      entry = "${packages.releaser}/bin/releaser lint-commit -c release.yaml";
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

    a-skills-sync = {
      enable = true;
      name = "Vendored skills";
      entry = "${packages.skills-sync}/bin/skills-sync sync --tier pre-commit";
      pass_filenames = false;
      language = "system";
    };

    # `dlint ci-wiring` is the successor to the deleted `workflows.sh wiring` mode.
    # The absolute store path is a safety property, not a style preference: a missing
    # package fails here at nix evaluation, loudly, and the shell will not build. A
    # bare `dlint` name would instead fail at runtime with exit 127 - the code
    # expectRedBecause reports as "could not prove sabotage" - so the mutation arm
    # would refuse for the wrong reason while the baseline arm merely failed.
    a-workflows = {
      enable = true;
      name = "Workflow wiring and release policy";
      entry = "${packages.atomiutils}/bin/bash -c '${packages.dlint}/bin/dlint ci-wiring && ( export PATH=${validator-runtime}/bin; ${packages.atomiutils}/bin/bash scripts/validate/workflows.sh release-trigger && ${packages.atomiutils}/bin/bash scripts/validate/workflows.sh release-concurrency )'";
      files = "^\\.github/workflows/.*\\.ya?ml$";
      pass_filenames = false;
      language = "system";
    };

    # Kept on this node under B4's child-ahead clause, and nominated for hoist to the
    # parent. `.dlint.json` configures no workflow-naming check, so this mode has no
    # successor to move to; deleting it alongside `wiring` would have dropped the
    # check in silence, because a battery that no longer runs a check cannot report
    # that the check is gone.
    a-workflow-names = {
      enable = true;
      name = "CI/CD workflow names";
      entry = validator "scripts/validate/workflows.sh workflow-names";
      files = "^\\.github/workflows/.*\\.ya?ml$";
      pass_filenames = false;
      language = "system";
    };

    # ### dotnet-base-hooks
    # #### source: dotnet-base
    a-dotnet-typecheck = {
      enable = true;
      name = ".NET typecheck";
      entry = "${packages.dotnet-sdk_10}/bin/dotnet build dotnet-base.slnx -c Release -m:1 /nodeReuse:false /p:UseSharedCompilation=false";
      files = "^(.*\\.cs|.*\\.csproj|Directory\\.Build\\.props|Directory\\.Packages\\.props|dotnet-base\\.slnx|global\\.json)$";
      pass_filenames = false;
      language = "system";
    };

    a-dotnet-vulnerability = {
      enable = true;
      name = ".NET vulnerability audit";
      entry = "${packages.dotnet-sdk_10}/bin/dotnet restore dotnet-base.slnx --force-evaluate -p:NuGetAudit=true -p:NuGetAuditMode=all -warnaserror";
      files = "^(.*\\.csproj|Directory\\.Build\\.props|Directory\\.Packages\\.props|dotnet-base\\.slnx|global\\.json)$";
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

    a-dotnet-release-types = {
      enable = true;
      name = ".NET release type vocabulary";
      entry = validator "scripts/validate/dotnet-release.sh";
      files = "^release\\.yaml$";
      pass_filenames = false;
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
  };
})
// {
  fetch-deps = dotnetlint-project.fetch-deps;
}
