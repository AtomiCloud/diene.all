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
    # set. diene_api_engine needs the FULL Flutter SDK, not just `flutter.dart`:
    # it depends on diene_auth_engine for the IAuth / ResourceKey / ResourceToken
    # seam its per-backend tokens resolve through, and that package declares
    # `flutter: '>=3.24.0'`. Measured rather than reasoned — `dart pub get` on a
    # manifest whose only dependency is diene_auth_engine ^1.0.1 fails with
    # "requires the Flutter SDK, version solving failed. Flutter users should use
    # `flutter pub` instead of `dart pub`" — so `flutter pub get` / `flutter test`
    # are the only invocations that can resolve and run this member.
    # `dart` above is retained UNCHANGED and still serves every pure-Dart gate
    # (notably `dart format`, which is SDK-agnostic).
    lib-dart-api-engine-packages = (
      with pkgs-unstable;
      {
        inherit flutter;
      }
    );
  };
in
with all;
nix-2605 // nix-unstable // atomipkgs // dart-lib-packages // lib-dart-api-engine-packages
