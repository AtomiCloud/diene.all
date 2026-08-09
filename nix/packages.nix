{
  atomi,
  pkgs-2605,
  pkgs-unstable,
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
          cyanprint
          dlint
          infralint
          infrautils
          releaser
          skills-sync
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
          # ### bun-base-packages
          # #### source: bun-base
          bun
          nodejs
          docker-client
          git
          go-task
          infisical
          jq
          kubernetes-helm
          nix
          pre-commit
          shellcheck
          treefmt
          yq-go
          # ### bun-consumer-packages
          # #### source: bun-consumer
          minio-client
          postgresql
          ;
      }
    );

    # ### nix-unstable
    # #### source: main
    nix-unstable = (
      with pkgs-unstable;
      {
      }
    );

  };
in
with all;
nix-2605 // nix-unstable // atomipkgs
