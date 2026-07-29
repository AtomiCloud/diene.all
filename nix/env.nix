{ pkgs, packages }:
with packages;
{
  # ### workspace-dev
  # #### source: workspace
  dev = [
    git
    go-task
    infisical
    jq
    pls
    sg
    skopeo
  ];

  # ### workspace-lint
  # #### source: workspace
  lint = [
    actionlint
    infralint
    kubeconform
    kubernetes-helm
    kyverno
    pre-commit
    ripgrep
    shellcheck
    treefmt
    yq-go
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
    docker-client
    git
    go-task
    infisical
    jq
    kubeconform
    kubernetes-helm
    kyverno
    pls
    ripgrep
    shellcheck
    skopeo
    yq-go
  ];

  # ### workspace-releaser-bootstrap
  # #### source: workspace
  # C2: sg is retained only until tools/releaser is published at step 2p.
  releaser = [
    sg
  ];

  # ### nix-root-system
  # #### source: main
  system = [
    atomiutils
    infrautils
  ];
}
