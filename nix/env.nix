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
    # ### lib-dart-e2e-dev
    # #### source: lib/dart/e2e
    # FORK, not inheritance: diene_e2e is the family VERSION TRAIN, so it depends
    # on every member — including diene_auth_engine and diene_api_engine, which
    # both declare `flutter: '>=3.24.0'`. Measured, not reasoned: `dart pub get`
    # on this manifest refuses outright with "Flutter users should use
    # `flutter pub` instead of `dart pub`", and plain `flutter pub get` in the
    # inherited dart-only shell fails with "command 'flutter' not found on PATH".
    # So this node's resolve/test/publish gates need `flutter`, not just
    # `flutter.dart`. Same fork api-engine and auth-engine each documented.
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
    # ### lib-dart-e2e-main
    # #### source: lib/dart/e2e
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
