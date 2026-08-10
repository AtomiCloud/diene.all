{ pkgs, packages }:
with packages;
{
  dev = [
    dart
    git
    go-task
    infisical
    releaser
    # FORK, not inheritance: diene_api_engine depends on the Flutter SDK because
    # diene_auth_engine (the IAuth seam its per-backend tokens key off) declares
    # `flutter: '>=3.24.0'`. Measured — `dart pub get` refuses the manifest
    # outright — so its resolve/test/publish gates need `flutter`, not just
    # `flutter.dart`. Same fork auth-engine documented; see
    # exec/nodes/lib__dart__api-engine/evidence/flutter-toolchain-delta.md.
    flutter
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

  main = [
    cyanprint
    dart
    git
    go-task
    infisical
    shellcheck
    # `main` is the only group present in ALL FOUR shells (cd/ci/default/
    # releaser). The pre-commit hooks that run `flutter test` execute in
    # `.#default` while the CI gates run in `.#ci`, so flutter must be here,
    # mirroring exactly how dart-lib placed `dart`. Putting it in `dev` alone
    # would leave every CI gate without a Flutter SDK.
    flutter
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
