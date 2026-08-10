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
  };
in
with all;
nix-2605 // nix-unstable // atomipkgs // dart-lib-packages
