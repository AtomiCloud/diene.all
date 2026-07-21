{
  packages,
  formatter,
  pkgs,
  pre-commit-lib,
}:
pre-commit-lib.run {
  src = ../.;

  hooks = {
    treefmt = {
      enable = true;
      package = formatter;
      excludes = [
        "^\.claude/skills/vendor/"
        "^CHANGELOG\.md$"
        "^Changelog\.md$"
        "^docs/developer/CommitConventions\.md$"
        "^infra/root_chart/"
      ];
    };

    a-dart-format = {
      enable = true;
      name = "Dart format";
      entry = "${packages.flutter}/bin/dart format --output=none --set-exit-if-changed lib/diene_core_utils.dart lib/src test tool";
      files = "^(lib|test|tool)/.*[.]dart$";
      pass_filenames = false;
      language = "system";
    };

    a-dart-analyze = {
      enable = true;
      name = "Dart analyze";
      entry = "${packages.flutter}/bin/dart analyze";
      files = "^(lib|test|tool)/.*[.]dart$|^(pubspec|analysis_options)[.]yaml$";
      pass_filenames = false;
      language = "system";
    };

    a-dart-test = {
      enable = true;
      name = "Dart unit tests";
      entry = "${packages.flutter}/bin/dart test";
      files = "^(lib|test)/.*[.]dart$|^pubspec[.]yaml$";
      pass_filenames = false;
      language = "system";
    };

    a-dart-deadcode = {
      enable = true;
      name = "Dart dead-code passes";
      entry = "${packages.pls}/bin/pls deadcode";
      files = "^(lib|test|tool)/.*[.]dart$|^Taskfile[.]yaml$";
      pass_filenames = false;
      language = "system";
    };

    a-dart-manifest-guard = {
      enable = true;
      name = "Dart manifest tag guard";
      entry = "${packages.bash}/bin/bash -c './scripts/validate/manifest-tag.sh v$(yq .version pubspec.yaml)'";
      files = "^(pubspec[.]yaml|VERSION|scripts/validate/manifest-tag[.]sh)$";
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
  };
}
