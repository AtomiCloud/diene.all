{
  packages,
  formatter,
  pkgs,
  pre-commit-lib,
  env,
}:
let
  # toolchain-smoke asserts the DECLARED env lists actually provide their binaries.
  envPath = pkgs.lib.makeBinPath (env.system ++ env.main ++ env.lint ++ env.dev);
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

    # -x + SCRIPTDIR: staged-file batching splits scripts from their sources,
    # so ShellCheck must follow source= directives itself.
    a-shellcheck = {
      enable = true;
      name = "Shellcheck";
      entry = "${packages.shellcheck}/bin/shellcheck -x --source-path=SCRIPTDIR";
      files = ".*\\.sh$";
      pass_filenames = true;
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
    # `flutter analyze` implicitly runs `flutter pub get`, which on a fresh
    # checkout (no `.dart_tool`) can leave the tree dirty and trip pre-commit's
    # "files were modified by this hook" guard. Resolve dependencies explicitly
    # and fail-closed (`--enforce-lockfile` never rewrites the tracked lock),
    # then analyze with `--no-pub` so the gate cannot mutate tracked files.
    a-flutter-analyze = {
      enable = true;
      name = "Flutter analyze";
      entry = "${packages.bash}/bin/bash -c '${packages.flutter}/bin/flutter pub get --enforce-lockfile && ${packages.flutter}/bin/flutter analyze --no-pub'";
      files = "^(lib|test)/.*[.]dart$|^(pubspec|analysis_options)[.]yaml$";
      pass_filenames = false;
      language = "system";
    };

    # Same hermeticity guard as a-flutter-analyze: `flutter test` implicitly
    # runs `flutter pub get`, which on a fresh checkout can dirty the tree and
    # trip pre-commit's "files were modified by this hook" guard. Resolve
    # dependencies explicitly and fail-closed, then test with `--no-pub`.
    a-flutter-test = {
      enable = true;
      name = "Flutter unit and widget tests";
      entry = "${packages.bash}/bin/bash -c '${packages.flutter}/bin/flutter pub get --enforce-lockfile && ${packages.flutter}/bin/flutter test --no-pub'";
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
      files = "^(scripts/release/bump[.]sh|release[.]yaml|pubspec[.]yaml)$";
      pass_filenames = false;
      language = "system";
    };
  };
}
