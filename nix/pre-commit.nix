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

    # flake.nix says every nixpkgs input is pinned to an exact commit and that nothing
    # validates it. This is that validation. It guards the ROOT's nixpkgs inputs only -
    # the transitive closure floats on channels legitimately and is not ours to police.
    a-nixpkgs-pin = {
      enable = true;
      name = "Nixpkgs pin honesty";
      entry = "${packages.atomiutils}/bin/bash -c 'export PATH=${validator-runtime}/bin; exec ${packages.atomiutils}/bin/bash scripts/validate/nixpkgs-pin.sh'";
      files = "^flake\\.(nix|lock)$";
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

    # `workflow-policy` and `workflows.sh` assert the same five values while the
    # migration is in flight, so neither gates the other: `&&` would stop the
    # second the moment the first refused, and the case it would hide is the one
    # the transition is about. Their verdicts are compared, and a DISAGREEMENT is
    # reported as its own fact - "both refused" and "they disagreed" are different
    # findings and only the second says anything about deleting the incumbent.
    # Which of the two spoke stays readable from the message shape: `dlint` names
    # the file, the path and the value it expected; the script prints its reason
    # alone.
    a-workflows = {
      enable = true;
      name = "Workflow wiring and release policy";
      entry = "${packages.atomiutils}/bin/bash -c 'c=0; p=0; s=0; ${packages.dlint}/bin/dlint ci-wiring || c=$?; ${packages.dlint}/bin/dlint workflow-policy || p=$?; ( export PATH=${validator-runtime}/bin; ${packages.atomiutils}/bin/bash scripts/validate/workflows.sh release-trigger && ${packages.atomiutils}/bin/bash scripts/validate/workflows.sh release-concurrency ) || s=$?; if [ $p -ne 0 ] && [ $s -eq 0 ]; then echo \"❌ release policy DISAGREEMENT: dlint workflow-policy refused what scripts/validate/workflows.sh accepted, so the wired check is STRICTER than the incumbent it would replace.\" >&2; elif [ $p -eq 0 ] && [ $s -ne 0 ]; then echo \"❌ release policy DISAGREEMENT: scripts/validate/workflows.sh refused what dlint workflow-policy accepted, so the wired check MISSES a fault the incumbent catches.\" >&2; fi; r=$c; [ $p -gt $r ] && r=$p; [ $s -gt $r ] && r=$s; exit $r'";
      files = "^\\.github/workflows/.*\\.ya?ml$";
      pass_filenames = false;
      language = "system";
    };
  };
}
