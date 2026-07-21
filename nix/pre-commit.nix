{
  packages,
  formatter,
  pkgs,
  pre-commit-lib,
}:
let
  validator-runtime = pkgs.buildEnv {
    name = "dart-library-validator-runtime";
    paths = [
      packages.bash
      packages.flutter
      packages.git
      packages.infisical
      packages.ripgrep
      packages.shellcheck
      packages.yq-go
      pkgs.coreutils
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
        "^Changelog[.]md$"
        "^docs/developer/CommitConventions[.]md$"
      ];
    };

    a-dart-format = {
      enable = true;
      name = "Dart format";
      entry = "${packages.flutter}/bin/dart format --output=none --set-exit-if-changed lib test";
      files = "^(lib|test)/.*[.]dart$";
      pass_filenames = false;
      language = "system";
    };

    a-dart-analyze = {
      enable = true;
      name = "Dart analyze";
      entry = "${packages.flutter}/bin/dart analyze";
      files = "^(lib|test)/.*[.]dart$|^(pubspec|analysis_options)[.]yaml$";
      pass_filenames = false;
      language = "system";
    };

    a-dart-test = {
      enable = true;
      name = "Dart unit and C0 tests";
      entry = "${packages.flutter}/bin/dart test test/unit test/conformance";
      files = "^(lib|test)/.*[.]dart$|^pubspec[.]yaml$";
      pass_filenames = false;
      language = "system";
    };

    a-dart-meta = {
      enable = true;
      name = "Dart TestHelper meta tests";
      entry = "${packages.flutter}/bin/dart test test/meta";
      files = "^(lib/test_helper|test/meta/).*[.]dart$|^pubspec[.]yaml$";
      pass_filenames = false;
      language = "system";
    };

    a-dart-coverage = {
      enable = true;
      name = "Dart scoped coverage ledgers";
      entry = validator "scripts/local/coverage.sh unit && scripts/local/coverage.sh meta";
      files = "^(lib|test)/.*[.]dart$|^pubspec[.]yaml$";
      pass_filenames = false;
      language = "system";
    };

    a-dart-deadcode = {
      enable = true;
      name = "Dart whole-package dead code";
      entry = validator "scripts/validate/dead-code.sh whole";
      files = "^(lib|test)/.*[.]dart$|^(pubspec|analysis_options)[.]yaml$";
      pass_filenames = false;
      language = "system";
    };

    a-dart-deadcode-production = {
      enable = true;
      name = "Dart production dead code";
      entry = validator "scripts/validate/dead-code.sh production";
      files = "^lib/.*[.]dart$|^(pubspec|analysis_options)[.]yaml$";
      pass_filenames = false;
      language = "system";
    };

    a-publish-version = {
      enable = true;
      name = "Dart publish version guard";
      entry = validator "scripts/validate/publish-version.sh v$(tr -d '[:space:]' <VERSION)";
      files = "^(pubspec[.]yaml|VERSION|scripts/validate/publish-version[.]sh)$";
      pass_filenames = false;
      language = "system";
    };

    a-release-stamp = {
      enable = true;
      name = "Dart release stamping";
      entry = validator "scripts/validate/release-pubspec.sh";
      files = "^(pubspec[.]yaml|VERSION|atomi_release[.]yaml|scripts/release/bump[.]sh|scripts/validate/release-pubspec[.]sh)$";
      pass_filenames = false;
      language = "system";
    };

    a-actionlint = {
      enable = true;
      name = "GitHub Actions lint";
      entry = "${packages.actionlint}/bin/actionlint";
      files = "^[.]github/workflows/.*[.]ya?ml$";
      pass_filenames = true;
      language = "system";
    };

    a-enforce-exec = {
      enable = true;
      name = "Executable shell scripts";
      entry = validator "scripts/validate/executable-shells.sh";
      files = ".*[.]sh$";
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

    a-shellcheck = {
      enable = true;
      name = "Shellcheck";
      entry = "${packages.shellcheck}/bin/shellcheck";
      files = ".*[.]sh$";
      pass_filenames = true;
      language = "system";
    };

    a-markdownlint = {
      enable = true;
      name = "Markdown lint";
      entry = "${pkgs.markdownlint-cli2}/bin/markdownlint-cli2";
      files = "^(README[.]md|CHANGELOG[.]md|doc/.*[.]md|skills/.*/SKILL[.]md)$";
      pass_filenames = true;
      language = "system";
    };
  };
}
