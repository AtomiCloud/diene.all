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
      packages.bun
      packages.flutter
      packages.git
      packages.jq
      packages.ripgrep
      packages.yq-go
      pkgs.coreutils
      pkgs.diffutils
      pkgs.findutils
      pkgs.gawk
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

    # ### flutter-base-hooks
    # #### source: flutter-base
    a-flutter-analyze = {
      enable = true;
      name = "Flutter analyze";
      entry = "${packages.flutter}/bin/flutter analyze";
      files = "^(lib|test)/.*[.]dart$|^(pubspec|analysis_options)[.]yaml$";
      pass_filenames = false;
      language = "system";
    };

    a-flutter-test = {
      enable = true;
      name = "Flutter unit and widget tests";
      entry = "${packages.flutter}/bin/flutter test";
      files = "^(lib|test)/.*[.]dart$|^pubspec[.]yaml$";
      pass_filenames = false;
      language = "system";
    };

    a-flutter-lpsm = {
      enable = true;
      name = "Flutter LPSM tokenization";
      entry = validator "scripts/ci/lpsm-lint.sh";
      files = "^(lpsm[.]yaml|pubspec[.]yaml|config/.*[.]yaml|android/.*|ios/.*)$";
      pass_filenames = false;
      language = "system";
    };

    a-flutter-config = {
      enable = true;
      name = "Flutter config layering";
      entry = validator "scripts/validate/config.sh";
      files = "^(config/.*[.]yaml|lib/config/.*[.]dart|test/config_test[.]dart)$";
      pass_filenames = false;
      language = "system";
    };

    a-flutter-config-schema = {
      enable = true;
      name = "Flutter config schema freshness";
      entry = validator "scripts/validate/generated.sh config";
      files = "^(config/schema[.]json|tool/generate-config-schema[.]ts)$";
      pass_filenames = false;
      language = "system";
    };

    a-flutter-sdk-freshness = {
      enable = true;
      name = "Flutter OA3 SDK freshness";
      entry = validator "scripts/validate/generated.sh sdk";
      files = "^(openapi/.*|swagger_parser[.]yaml|lib/generated/.*)$";
      pass_filenames = false;
      language = "system";
    };

    a-flutter-slang-freshness = {
      enable = true;
      name = "Flutter Slang freshness";
      entry = validator "scripts/validate/generated.sh translations";
      files = "^(slang[.]yaml|lib/i18n/.*)$";
      pass_filenames = false;
      language = "system";
    };

    a-flutter-translation-compile = {
      enable = true;
      name = "Flutter translation compile";
      entry = validator "scripts/validate/translations-compile.sh";
      files = "^lib/i18n/.*";
      pass_filenames = false;
      language = "system";
    };

    a-flutter-rebrand = {
      enable = true;
      name = "Flutter rebrand guard";
      entry = validator "scripts/validate/rebrand.sh";
      files = "^((lib|config|android|ios|assets)/.*|pubspec[.]yaml|lpsm[.]yaml)$";
      pass_filenames = false;
      language = "system";
    };

    a-flutter-landscape-policy = {
      enable = true;
      name = "Flutter build-time landscape policy";
      entry = validator "scripts/validate/landscape-policy.sh";
      files = "^lib/.*[.]dart$";
      pass_filenames = false;
      language = "system";
    };

    a-flutter-build-numbers = {
      enable = true;
      name = "Flutter store build-number guards";
      entry = validator "scripts/validate/build-numbers.sh";
      files = "^scripts/ci/lib-(ios|android)[.]sh$";
      pass_filenames = false;
      language = "system";
    };

    a-flutter-signing-doctors = {
      enable = true;
      name = "Flutter signing and stamp doctors";
      entry = validator "scripts/validate/signing-doctors.sh";
      files = "^(lpsm[.]yaml|ios/.*|scripts/ci/(doctor-ios|stamp-ios|stamp-android|ios-signing-targets)[.]sh)$";
      pass_filenames = false;
      language = "system";
    };

    a-flutter-mobile-workflows = {
      enable = true;
      name = "Flutter mobile workflow wiring";
      entry = validator "scripts/validate/mobile-workflows.sh";
      files = "^([.]github/workflows/.*[.]ya?ml|scripts/ci/.*[.]sh)$";
      pass_filenames = false;
      language = "system";
    };

    a-flutter-cd-matrix = {
      enable = true;
      name = "Flutter CD matrix shape";
      entry = validator "scripts/validate/cd-matrix.sh";
      files = "^(lpsm[.]yaml|scripts/ci/cd-matrix[.]sh|[.]github/workflows/cd[.]yaml)$";
      pass_filenames = false;
      language = "system";
    };

    a-flutter-release-pubspec = {
      enable = true;
      name = "Flutter release pubspec stamping";
      entry = validator "scripts/validate/release-pubspec.sh";
      files = "^(scripts/release/bump[.]sh|atomi_release[.]yaml|pubspec[.]yaml)$";
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
