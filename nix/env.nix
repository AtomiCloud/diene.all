{ pkgs, packages }:
with packages;
{
  dev = [
    dart
    git
    go-task
    infisical
    releaser
    # FORK, not inheritance: diene_e2e is the family VERSION TRAIN, so it depends
    # on every member — including diene_auth_engine and diene_api_engine, which
    # both declare `flutter: '>=3.24.0'`. Measured, not reasoned: `dart pub get`
    # on this manifest refuses outright with "Flutter users should use
    # `flutter pub` instead of `dart pub`", and plain `flutter pub get` in the
    # inherited dart-only shell fails with "command 'flutter' not found on PATH".
    # So this node's resolve/test/publish gates need `flutter`, not just
    # `flutter.dart`. Same fork api-engine and auth-engine each documented.
    #
    # Both `dart` and `flutter` in one list is fine: these are mkShell inputs,
    # where later entries shadow earlier ones, so flutter's bundled `dart` wins
    # on PATH exactly as it did pre-merge.
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
