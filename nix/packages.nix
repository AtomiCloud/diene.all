{
  atomi,
  pkgs-2605,
  pkgs-unstable,
  ...
}:
let
  all = rec {
    # ### nix-root
    # #### source: main
    atomipkgs = (
      with atomi;
      {
        inherit
          atomiutils
          infralint
          infrautils
          pls
          sg
          ;
      }
    );

    # ### workspace
    # #### source: workspace
    nix-2605 = (
      with pkgs-2605;
      {
        inherit
          actionlint
          bash
          entr
          git
          gitlint
          go-task
          infisical
          jq
          nodejs
          pre-commit
          ripgrep
          shellcheck
          treefmt
          yq-go
          ;
      }
    );

    # ### dart-result-packages
    # #### source: lib/dart/result
    nix-unstable = {
      inherit (pkgs-unstable) dart;
    };
  };
in
with all;
atomipkgs // nix-2605 // nix-unstable
