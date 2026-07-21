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
  hooks = {
    treefmt = {
      enable = true;
      package = formatter;
      excludes = [
        "^\\.claude/skills/vendor/"
        "^CHANGELOG\\.md$"
        "^docs/developer/CommitConventions\\.md$"
      ];
    };

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

    a-dart-analyze = {
      enable = true;
      name = "Dart analyze";
      entry = "${packages.flutter}/bin/dart analyze";
      files = "^(lib|test|example)/.*[.]dart$|^(pubspec|analysis_options)[.]yaml$";
      pass_filenames = false;
      language = "system";
    };

    a-dart-test = {
      enable = true;
      name = "Dart tests";
      entry = "${packages.flutter}/bin/dart test";
      files = "^(lib|test)/.*[.]dart$|^pubspec[.]yaml$";
      pass_filenames = false;
      language = "system";
    };

    a-dart-deadcode = {
      enable = true;
      name = "Dart dead-code passes";
      entry = validator "scripts/validate/deadcode.sh all";
      files = "^(lib|test|example)/.*[.]dart$|^analysis_options[.]yaml$";
      pass_filenames = false;
      language = "system";
    };

    a-dart-publish-version = {
      enable = true;
      name = "Dart publish manifest guard";
      entry = validator "scripts/validate/dart-publish-version.sh v0.1.0";
      files = "^(VERSION|pubspec[.]yaml|scripts/(ci/publish|validate/dart-publish-version)[.]sh)$";
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

    a-shellcheck = {
      enable = true;
      name = "Shellcheck";
      entry = "${packages.shellcheck}/bin/shellcheck";
      files = ".*\\.sh$";
      pass_filenames = true;
      language = "system";
    };

    a-markdownlint = {
      enable = true;
      name = "Markdown lint";
      entry = "${pkgs.markdownlint-cli2}/bin/markdownlint-cli2";
      files = "^(README|doc/configuration|skills/diene-config-usage/SKILL)[.]md$";
      pass_filenames = true;
      language = "system";
    };
  };
}
