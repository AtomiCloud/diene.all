{
  atomi,
  pkgs,
  pkgs-2605,
  pkgs-unstable,
}:
let
  cyanprintSource = pkgs.fetchFromGitHub {
    owner = "AtomiCloud";
    repo = "sulfone.lite";
    rev = "2d238d5c4c7a0b4f72d12a31e177117d1b0f8f7b";
    hash = "sha256-iLFbFcIFO84ex/oSI0QXK6Vlh9PciT+m+KJ1F3V2dNk=";
  };
  cyanprintPackages = import "${cyanprintSource}/nix/packages.nix" {
    inherit
      atomi
      pkgs
      pkgs-2605
      pkgs-unstable
      ;
  };
  cyanprint = cyanprintPackages.cyanprint;
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
          docker-client
          git
          gitlint
          go-task
          infisical
          jq
          kubeconform
          kubernetes-helm
          kyverno
          pre-commit
          ripgrep
          shellcheck
          skopeo
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

    root = {
      inherit cyanprint helm-schema;
    };
  };
in
with all;
atomipkgs // nix-2605 // nix-unstable // root
