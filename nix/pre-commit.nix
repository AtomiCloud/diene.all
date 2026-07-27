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
      # ### lib-dart-auth-engine-validator-runtime
      # #### source: lib/dart/auth-engine
      # SUPERSEDES the inherited `packages.dart` entry — deliberately replacing
      # it, not adding alongside it.
      #
      # The validator wrapper below sets PATH to EXACTLY this buildEnv, so a
      # tool absent here is `command not found` (exit 127) inside every hook, no
      # matter what nix/env.nix puts in the dev shell. diene_auth_engine is a
      # Flutter package, so its analyze/test/package validators shell out to
      # `flutter`.
      #
      # `packages.dart` CANNOT be listed as well: `dart = flutter.dart`, so both
      # paths ship `dartdoc_options.yaml` and buildEnv aborts with "two given
      # paths contain a conflicting subpath". Nothing is lost by dropping it —
      # flutter-wrapped/bin/dart is a symlink to the very same
      # dart-3.12.2/bin/dart that `packages.dart` resolves to, so `dart` stays
      # on the hook PATH at the identical version.
      packages.flutter
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
        # ### lib-dart-auth-engine-formatter
        # #### source: lib/dart/auth-engine
        # Digest-bound C0 projection — see the matching keyed block in
        # nix/fmt.nix. Excluded at BOTH levels deliberately: fmt.nix governs a
        # direct `treefmt` run, this list governs the pre-commit hook, and only
        # the hook was observed rewriting the fixture (10976 -> 10910 bytes)
        # while a direct prettier run left it byte-identical. Excluding one level
        # only would have left that asymmetry live.
        "^packages/diene_auth_engine/test/fixtures/c0/"
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

    a-workflow-wiring = {
      enable = true;
      name = "Workflow job-to-script wiring";
      entry = validator "scripts/validate/workflows.sh wiring";
      files = "^\\.github/workflows/.*\\.ya?ml$";
      pass_filenames = false;
      language = "system";
    };

    # ### dart-lib-hooks
    # #### source: dart-lib
    a-dart-format = {
      enable = true;
      name = "Dart format";
      entry = "${packages.dart}/bin/dart format --output=none --set-exit-if-changed";
      files = "^packages/diene_auth_engine/(lib|test|example)/.*[.]dart$";
      pass_filenames = true;
      language = "system";
    };

    a-dart-analyze = {
      enable = true;
      name = "Dart analyze";
      entry = validator "scripts/ci/analyze.sh";
      files = "^packages/diene_auth_engine/(lib|test|example|tool)/.*[.]dart$|^(packages/diene_auth_engine/(pubspec|analysis_options)|pubspec)[.]yaml$";
      pass_filenames = false;
      language = "system";
    };

    a-dart-test = {
      enable = true;
      name = "Dart unit, C0, and meta tests";
      entry = validator "scripts/ci/test-all.sh";
      files = "^packages/diene_auth_engine/(lib|test)/.*[.]dart$|^(packages/diene_auth_engine/pubspec|pubspec)[.]yaml$";
      pass_filenames = false;
      language = "system";
    };

    a-dart-package = {
      enable = true;
      name = "Dart package and TestHelper boundary";
      entry = validator "scripts/validate/dart-package.sh";
      # Also triggers on the C0 projection inputs and outputs, so a moved frozen
      # release or a hand-edited fixture is caught at commit time rather than
      # leaving the conformance tier green but no longer bound to the contract.
      files = "^(packages/diene_auth_engine/(lib/.*[.]dart|tool/gen_c0_projection[.]dart|test/fixtures/c0/.*|pubspec[.]yaml|README[.]md|CHANGELOG[.]md|LICENSE|skills/.*|doc/diene_auth_engine[.]md)|contracts/c0/.*|pubspec[.]yaml|VERSION)$";
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
