{
  atomi,
  pkgs-2605,
  pkgs-unstable,
  releaser-pkg,
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
          ;
      }
    );

    nix-2605 = (
      with pkgs-2605;
      {
        inherit
          actionlint
          git
          go-task
          infisical
          pre-commit
          shellcheck
          treefmt
          ;
      }
    );

    nix-unstable = (
      with pkgs-unstable;
      {
      }
    );

    releaser-pkgs = {
      releaser = releaser-pkg;
    };
  };
in
with all;
atomipkgs // nix-2605 // nix-unstable // releaser-pkgs
