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

    # The releaser validates the message against `atomi_release.yaml`, so the commit
    # vocabulary has exactly one authority and there is no second gitlint file.
    #
    # This hook was deleted in the previous round for a narrow reason worth keeping
    # in view: no shell here provided the binary, and because entering a dev shell
    # reinstalls hooks into the SHARED bare repository, a commit-msg hook whose
    # binary was missing broke plain `git commit` in every worktree of this
    # repository at once. The entry below is an absolute store path, not a PATH
    # lookup, so it resolves from any worktree and any shell - and it is proved by
    # real `git commit` runs in both directions, not by invoking the binary by hand.
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
      entry = validator "scripts/validate/skills-freshness.sh";
      pass_filenames = false;
      language = "system";
    };

    # Wiring keeps both of its halves - every referenced scripts/ci entry point
    # exists and is executable, and every orchestrator job resolves to a
    # repository-local reusable workflow that calls one - and shares this hook with
    # the two release-policy assertions, so the committer waits on one hook.
    #
    # Runner and cache LABELS are plain workflow configuration and are deliberately
    # not validated here (owner ruling, 2026-08-05). Do not add a mode back.
    a-workflows = {
      enable = true;
      name = "Workflow wiring and release policy";
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
