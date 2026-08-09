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
          # This node strips BOTH the helm axis and the docker axis, and the
          # aggregates carry both by CONTENT: infrautils ships helm, k3d,
          # kubectl, kubectx, kubens AND docker, dockerd, dockerd-rootless;
          # infralint ships helm-docs, helmlint AND hadolint, skopeo. A node
          # named for the absence of two axes cannot declare a bundle that
          # smuggles them back in. Unlike the parent, `infralint-docker` is NOT
          # taken here: the docker axis is exactly what this node strips.
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
