{
  atomi,
  pkgs,
  pkgs-2605,
  pkgs-unstable,
}:
let
  cyanprintVersion = "4.9.0";
  cyanprintSystem = pkgs.stdenv.hostPlatform.system;
  cyanprintPlatform =
    ({
      x86_64-linux = "linux_amd64";
      aarch64-linux = "linux_arm64";
      x86_64-darwin = "darwin_amd64";
      aarch64-darwin = "darwin_arm64";
    }).${cyanprintSystem};
  cyanprintHash =
    ({
      x86_64-linux = "sha256-z5whvbKPJTgyR5qWeYefN7NuTKY1pWaRkYDnyyaNG9k=";
      aarch64-linux = "sha256-SrhazRJbeK3vJHGvv0TwKHdz/ulqZM04qMtKgX0AJgA=";
      x86_64-darwin = "sha256-XIolxZN+KVf/Ui5/rQjg+k3OXLrbJuGGxh6iYkki+/k=";
      aarch64-darwin = "sha256-xugPBTO6CTixUjpq9PPq2WOQySci735gfuOXZSn75Ew=";
    }).${cyanprintSystem};
  cyanprint = pkgs.stdenvNoCC.mkDerivation {
    pname = "cyanprint";
    version = cyanprintVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/AtomiCloud/sulfone.lite/releases/download/v${cyanprintVersion}/cyanprint_${cyanprintVersion}_${cyanprintPlatform}.tar.gz";
      hash = cyanprintHash;
    };
    sourceRoot = ".";
    strictDeps = true;
    dontStrip = true;
    nativeBuildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.autoPatchelfHook ];
    buildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.glibc ];
    installPhase = ''
      runHook preInstall
      install -Dm755 cyanprint "$out/bin/cyanprint"
      runHook postInstall
    '';
    doInstallCheck = true;
    installCheckPhase = ''
      "$out/bin/cyanprint" --version | grep -Fx "cyanprint ${cyanprintVersion}"
    '';
    meta.mainProgram = "cyanprint";
  };
  all = rec {
    # ### go-base
    # #### source: go-base
    go-base = (
      with pkgs-2605;
      {
        deadcode = gotools;
        staticcheck = go-tools;
        go = pkgs-2605.go.overrideAttrs (
          finalAttrs: _previousAttrs: {
            version = "1.26.5";
            src = pkgs-2605.fetchurl {
              url = "https://go.dev/dl/go${finalAttrs.version}.src.tar.gz";
              hash = "sha256-SVvkvIcXasVnOS5bQRar2YRm0z17SdQedkzMaXay3EI=";
            };
          }
        );
        inherit
          gofumpt
          golangci-lint
          gotestsum
          govulncheck
          ;
      }
    );

    # ### operator-template
    # #### source: operator-template
    operator = (
      with pkgs-2605;
      {
        controller-gen = kubernetes-controller-tools;
        inherit kubebuilder setup-envtest;
        # Offline envtest asset directory: kube-apiserver + etcd + kubectl from the
        # pinned nixpkgs, so `KUBEBUILDER_ASSETS` never triggers a runtime download
        # (M14 cold-runner discipline). Consumed by the shell hook, not on PATH.
        envtest-assets = runCommandLocal "operator-envtest-assets" { } ''
          mkdir -p "$out"
          ln -s ${kubernetes}/bin/kube-apiserver "$out/kube-apiserver"
          ln -s ${etcd}/bin/etcd "$out/etcd"
          ln -s ${kubectl}/bin/kubectl "$out/kubectl"
        '';
      }
    );

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
      inherit cyanprint;
    };
  };
in
with all;
atomipkgs // nix-2605 // nix-unstable // root // go-base // operator
