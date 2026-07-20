{
  atomi,
  pkgs,
  pkgs-2605,
  pkgs-unstable,
}:
let
  cyanprintVersion = "4.8.0";
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
      x86_64-linux = "sha256-lxibv7rqcp0rQtvWb41ifxA+ORwt8yiSKM0NaRJmt1w=";
      aarch64-linux = "sha256-XDx6CtFS4doSeswYWyTPT0GHPDcW8tb6YEzd5QJuv78=";
      x86_64-darwin = "sha256-xGoTSpMkXAKdUm6NDDN75yfHu25nMgXP1hiIfGb9fvo=";
      aarch64-darwin = "sha256-7xLzKKCK5UiU1saHf8l1z1UuInQm1CTjowIlwpGRM7Y=";
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
    # ### dotnet-base
    # #### source: dotnet-base
    dotnet-base = {
      dotnetlint = atomi.dotnetlint.override { dotnetPackage = pkgs-2605.dotnet-sdk_10; };
      dn-inspect = atomi.dn-inspect.override { dotnetPackage = pkgs-2605.dotnet-sdk_10; };
      inherit (pkgs-2605) dotnet-sdk_10 gitlint;
    };

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
      inherit cyanprint;
    };
  };
in
with all;
atomipkgs // nix-2605 // nix-unstable // root // dotnet-base
