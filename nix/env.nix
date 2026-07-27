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
    # ### dart-lib-dev
    # #### source: dart-lib
    dart
    # ### lib-dart-api-engine-dev
    # #### source: lib/dart/api-engine
    # FORK, not inheritance: diene_api_engine depends on the Flutter SDK because
    # diene_auth_engine (the IAuth seam its per-backend tokens key off) declares
    # `flutter: '>=3.24.0'`. Measured — `dart pub get` refuses the manifest
    # outright — so its resolve/test/publish gates need `flutter`, not just
    # `flutter.dart`. Same fork auth-engine documented; see
    # exec/nodes/lib__dart__api-engine/evidence/flutter-toolchain-delta.md.
    flutter
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
    # ### dart-lib-lint
    # #### source: dart-lib
    gitlint
  ];

  # ### workspace-main
  # #### source: workspace
  main = [
    cyanprint
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
    # ### dart-lib-main
    # #### source: dart-lib
    dart
    # ### lib-dart-api-engine-main
    # #### source: lib/dart/api-engine
    # `main` is the only group present in ALL FOUR shells (cd/ci/default/
    # releaser). The pre-commit hooks that run `flutter test` execute in
    # `.#default` while the CI gates run in `.#ci`, so flutter must be here,
    # mirroring exactly how dart-lib placed `dart`. Putting it in `dev` alone
    # would leave every CI gate without a Flutter SDK.
    flutter
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
