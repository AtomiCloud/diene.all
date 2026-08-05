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
      entry = "releaser lint-commit -c atomi_release.yaml";
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
  };
}
