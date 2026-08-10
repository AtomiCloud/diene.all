{
  atomi,
  pkgs,
  pkgs-2605,
  pkgs-unstable,
}:
let
  all = rec {
    # ### dotnet-base
    # #### source: dotnet-base
    dotnet-base = {
      dotnetlint = atomi.dotnetlint.override { dotnetPackage = pkgs-2605.dotnet-sdk_10; };
      dn-inspect = atomi.dn-inspect.override { dotnetPackage = pkgs-2605.dotnet-sdk_10; };
      inherit (pkgs-2605) dotnet-sdk_10 xmlstarlet;
    };

    # ### nix-root
    # #### source: main
    atomipkgs = (
      with atomi;
      {
        inherit
          atomiutils
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
          docker-client
          git
          go-task
          infisical
          jq
          kubeconform
          kubernetes-helm
          kyverno
          nix
          pre-commit
          ripgrep
          shellcheck
          skopeo
          treefmt
          unzip
          xmlstarlet
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

    root = {
      # `cyanprint` is a REGISTRY EXPORT as of nix-registry v5.5.0. The hand-written
      # `pkgs.stdenvNoCC.mkDerivation` that used to stand here - with its own version
      # pin, its per-system platform and hash lookups, and its whole derivation body -
      # is DELETED, not disabled. The capability is KEPT: it now arrives from `atomi`,
      # which is exactly what the hoist was for. Authoring a derivation inside a node
      # was refused by two independent instruments at two layers - `dlint`'s
      # `no-custom-derivations` check and the published resolver's merger - and both
      # refusals named this one construct. Do not reintroduce it here.
      #
      # Naming the construct in prose is only safe because `no-custom-derivations`
      # became comment-aware in nix-registry v5.6.0, which is the revision this node's
      # flake.lock pins. Before that it was a plain text scan and this very comment
      # made the check refuse - measured, on this file. If the pin is ever moved BACK
      # below v5.6.0, this paragraph turns into a false positive.
      inherit (atomi) cyanprint;
    };
  };
in
with all;
nix-2605 // nix-unstable // atomipkgs // root // dotnet-base
