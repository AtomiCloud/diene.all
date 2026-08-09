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
          # The axis-pure slices, not the `infralint`/`infrautils` aggregates. The
          # aggregates carry BOTH stripped axes by CONTENT - infralint ships
          # hadolint, skopeo, helm-docs and helmlint, infrautils ships docker,
          # dockerd and helm - so this node cannot declare them and still be the
          # node its name describes. Neither docker slice is taken: this node
          # strips that axis, and `docker-client` below is a separate pre-existing
          # declaration, not part of this swap.
          infralint-core
          infrautils-core
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
          nix
          pre-commit
          shellcheck
          treefmt
          yq-go
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
