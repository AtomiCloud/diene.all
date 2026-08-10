{ pkgs, packages }:
with packages;
{
  dev = [
    dart
    # diene_auth_engine depends on the Flutter SDK through logto_dart_sdk.
    flutter
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

  main = [
    cyanprint
    dart
    # Hooks run from both the default and CI shells, so Flutter belongs in the
    # shared main environment as well as the developer environment.
    flutter
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
