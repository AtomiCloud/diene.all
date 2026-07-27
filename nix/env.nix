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
    # ### lib-dart-auth-engine-dev
    # #### source: lib/dart/auth-engine
    # FORK, not inheritance: diene_auth_engine depends on the Flutter SDK
    # (logto_dart_sdk 3.0.0 requires environment.flutter >=1.17.0), so its
    # resolve/test/publish gates need `flutter`, not just `flutter.dart`.
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
    # ### lib-dart-auth-engine-main
    # #### source: lib/dart/auth-engine
    # `main` is the only group present in ALL FOUR shells (cd/ci/default/
    # releaser), and the pre-commit hooks that run `flutter test` execute in
    # `.#default` while the probe matrix runs in `.#ci` — so flutter must be
    # here, mirroring exactly how dart-lib placed `dart`. Putting it only in
    # `dev` would leave every CI gate without a Flutter SDK.
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
