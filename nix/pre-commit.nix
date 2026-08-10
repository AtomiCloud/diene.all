{
  packages,
  formatter,
  pkgs,
  pre-commit-lib,
  env,
  offline ? false,
}:
let
  # toolchain-smoke asserts the DECLARED env lists actually provide their binaries.
  envPath = pkgs.lib.makeBinPath (env.system ++ env.main ++ env.lint ++ env.dev);
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
      packages.dart
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

    # One invocation runs every check declared in dlint.yaml, so the checks this
    # node owns (`ci-wiring`, `workflow-policy`) are covered here rather than by
    # per-check hooks. Adding a check to dlint.yaml needs no edit in this file.
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
      files = "^(CLAUDE\\.md|README\\.md|docs/standards/.*\\.md|\\.claude/skills/[^/]+/SKILL\\.md)$";
      pass_filenames = true;
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

    a-dart-format = {
      enable = true;
      name = "Dart format";
      entry = "${packages.dart}/bin/dart format --output=none --set-exit-if-changed";
      files = "^packages/diene_config/(lib|test|example|tool)/.*[.]dart$";
      pass_filenames = true;
      language = "system";
    };

    a-dart-analyze = {
      enable = !offline;
      name = "Dart analyze";
      entry = validator "scripts/ci/analyze.sh";
      files = "^packages/diene_config/(lib|test|example|tool)/.*[.]dart$|^(packages/diene_config/(pubspec|analysis_options)|pubspec)[.]yaml$";
      pass_filenames = false;
      language = "system";
    };

    a-dart-test = {
      enable = !offline;
      name = "Dart unit, C0, and meta tests";
      entry = validator "scripts/ci/test-all.sh";
      files = "^packages/diene_config/(lib|test)/.*[.]dart$|^(packages/diene_config/pubspec|pubspec)[.]yaml$";
      pass_filenames = false;
      language = "system";
    };

    a-dart-package = {
      enable = !offline;
      name = "Dart package and TestHelper boundary";
      entry = validator "scripts/validate/dart-package.sh";
      files = "^(packages/diene_config/(lib/.*[.]dart|tool/gen_c0_projection[.]dart|test/fixtures/c0/.*|pubspec[.]yaml|README[.]md|CHANGELOG[.]md|LICENSE|skills/.*|doc/configuration[.]md)|contracts/c0/.*|scripts/validate/c0-release[.]sh|[.]prettierignore|pubspec[.]yaml|VERSION)$";
      pass_filenames = false;
      language = "system";
    };
  };
}
