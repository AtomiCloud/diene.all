{
  packages,
  formatter,
  pkgs,
  pre-commit-lib,
  offline ? false,
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
      packages.dart
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
      entry = "${packages.gitlint}/bin/gitlint --staged --msg-filename";
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

    a-dart-format = {
      enable = true;
      name = "Dart format";
      entry = "${packages.dart}/bin/dart format --output=none --set-exit-if-changed";
      files = "^packages/diene_dart_lib/(lib|test|example)/.*[.]dart$";
      pass_filenames = true;
      language = "system";
    };

    a-dart-analyze = {
      enable = !offline;
      name = "Dart analyze";
      entry = validator "scripts/ci/analyze.sh";
      files = "^packages/diene_dart_lib/(lib|test|example|tool)/.*[.]dart$|^(packages/diene_dart_lib/(pubspec|analysis_options)|pubspec)[.]yaml$";
      pass_filenames = false;
      language = "system";
    };

    a-dart-test = {
      enable = !offline;
      name = "Dart unit, C0, and meta tests";
      entry = validator "scripts/ci/test-all.sh";
      files = "^packages/diene_dart_lib/(lib|test)/.*[.]dart$|^(packages/diene_dart_lib/pubspec|pubspec)[.]yaml$";
      pass_filenames = false;
      language = "system";
    };

    a-dart-package = {
      enable = !offline;
      name = "Dart package and TestHelper boundary";
      entry = validator "scripts/validate/dart-package.sh";
      files = "^(packages/diene_dart_lib/(lib/.*[.]dart|pubspec[.]yaml|README[.]md|CHANGELOG[.]md|LICENSE|skills/.*|doc/diene_dart_lib[.]md)|pubspec[.]yaml|VERSION)$";
      pass_filenames = false;
      language = "system";
    };
  };
}
