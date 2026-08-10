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
          helm-schema
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
          gitlint
          go-task
          infisical
          nix
          pre-commit
          shellcheck
          treefmt
          # Wrapper toolchain. The parent trimmed these out of the shared list
          # along with its docker strip; this node's own gates still name them
          # (`nix/pre-commit.nix` validator-runtime, `scripts/validate/helm-wrapper.sh`,
          # `scripts/local/latest-chart-upstreams.sh`), so they stay.
          bash
          jq
          kubeconform
          kubernetes-helm
          kyverno
          ripgrep
          skopeo
          yq-go
          ;
        # Go toolchain for the Kargo YAML-engine integration test under
        # scripts/validate/kargo-yaml-update (pinned go 1.25.x).
        go = go_1_25;
      }
    );
  };
in
with all;
nix-2605 // nix-unstable // atomipkgs
