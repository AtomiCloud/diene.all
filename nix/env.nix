{ pkgs, packages }:
with packages;
{
  dev = [
    git
    go-task
    infisical
    releaser
  ];

  lint = [
    actionlint
    dlint
    infralint
    pre-commit
    shellcheck
    skills-sync
    treefmt
  ];

  # ### flutter-base-mobile
  # #### source: flutter-base
  mobile = [
    codemagic-cli-tools
    fastlane
    flutter
    resvg
    rsync
  ]
  ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [ cocoapods ];

  # ### flutter-base-android
  # #### source: flutter-base
  android = [
    androidsdk
    bundletool
    jdk17
    protobuf
    unzip
    zip
  ];

  # ### workspace-main
  # #### source: workspace
  main = [
    cyanprint
    bun
    git
    go-task
    infisical
    shellcheck
  ];

  releaser = [
    releaser
  ];

  system = [
    atomiutils
    infrautils
    nix
  ];
}
