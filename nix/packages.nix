{
  atomi,
  pkgs-2605,
  pkgs-unstable,
}:
let
  all = rec {
    atomipkgs = (
      with atomi;
      {
        inherit
          atomiutils
          cyanprint
          dlint
          infralint
          infrautils
          releaser
          skills-sync
          ;
      }
    );
    nix-unstable = (with pkgs-unstable; { });
    nix-2605 = (
      with pkgs-2605;
      {
        inherit
          actionlint
          git
          go-task
          infisical
          nix
          pre-commit
          shellcheck
          treefmt
          ;
      }
    );
    dart-lib-packages = (
      with pkgs-unstable;
      {
        dart = flutter.dart;
      }
    );

    # FORKED FROM THE PURE-DART FAMILY SHAPE, following the precedent auth-engine
    # set and api-engine followed. diene_e2e needs the FULL Flutter SDK, not just
    # `flutter.dart`, because it is the family VERSION TRAIN: it depends on all
    # seven members, two of which (diene_auth_engine, diene_api_engine) declare
    # `flutter: '>=3.24.0'`. Measured rather than reasoned — `dart pub get` on
    # this manifest refuses with "Flutter users should use `flutter pub` instead
    # of `dart pub`", and `flutter pub get` in the inherited dart-only shell dies
    # with "command 'flutter' not found on PATH". So `flutter pub get` /
    # `flutter test` are the only invocations that can resolve and run this
    # member. `dart` above is retained UNCHANGED and still serves every
    # pure-Dart gate (notably `dart format`, which is SDK-agnostic).
    lib-dart-e2e-packages = (
      with pkgs-unstable;
      {
        inherit flutter;
      }
    );
  };
in
with all;
nix-2605 // nix-unstable // atomipkgs // dart-lib-packages // lib-dart-e2e-packages
