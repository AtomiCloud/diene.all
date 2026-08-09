{
  atomi,
  pkgs,
  pkgs-2605,
  pkgs-unstable,
}:
let
  # `helm-schema` is this node's own payload: it is the Helm wrapper, and
  # `scripts/local/generate-chart-schema.sh` plus the `schema` and `schema-drift`
  # arms of `scripts/validate/helm-wrapper.sh` are built on it. The parent
  # dropped the whole `let` prelude when it retired its locally-built cyanprint
  # (which now comes from the registry as `atomi.cyanprint`, adopted below), and
  # that removal would have taken this wrapper with it. It is kept, and `pkgs` is
  # kept in the argument set because the wrapper needs it.
  helm-schema = pkgs.writeShellApplication {
    name = "helm-schema";
    runtimeInputs = [
      pkgs.kubernetes-helm
      pkgs.kubernetes-helmPlugins.helm-schema
    ];
    text = ''
      export HELM_PLUGINS="${pkgs.kubernetes-helmPlugins.helm-schema}"
      exec helm schema "$@"
    '';
  };
in
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
      }
    );

    root = {
      inherit helm-schema;
    };
  };
in
with all;
nix-2605 // nix-unstable // atomipkgs // root
