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
          # The axis-pure slices, not the `infralint`/`infrautils` aggregates.
          # The aggregates carry the helm axis by CONTENT — infralint ships
          # helm-docs and helmlint, infrautils ships helm — so a node whose
          # defining property is the absence of that axis cannot declare them
          # and still be telling the truth. `infralint-docker` is taken because
          # hadolint and skopeo are invoked here; `infrautils-docker` is not,
          # because `docker-client` below already provides the only binary of
          # it this node uses.
          infralint-core
          infralint-docker
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
