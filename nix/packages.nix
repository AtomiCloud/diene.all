{
  atomi,
  pkgs,
  pkgs-2605,
  pkgs-unstable,
  pkgs-android,
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
  # ### flutter-base-mobile-packages
  # #### source: flutter-base
  ruby-xcodeproj = pkgs-unstable.ruby.withPackages (rubyPackages: [ rubyPackages.xcodeproj ]);
  androidComposition = pkgs-android.androidenv.composeAndroidPackages {
    platformVersions = [
      "34"
      "35"
      "36"
    ];
    buildToolsVersions = [
      "35.0.0"
      "36.0.0"
    ];
    abiVersions = [
      "arm64-v8a"
      "x86_64"
    ];
    includeNDK = true;
    ndkVersions = [ "28.2.13676358" ];
    cmakeVersions = [ "3.22.1" ];
    includeEmulator = false;
    includeSystemImages = false;
    extraLicenses = [
      "android-googletv-license"
      "android-sdk-arm-dbt-license"
      "android-sdk-license"
      "android-sdk-preview-license"
      "google-gdk-license"
      "intel-android-extra-license"
      "intel-android-sysimage-license"
      "mips-android-sysimage-license"
    ];
  };
  all = rec {
    # ### nix-root
    # #### source: main
    atomipkgs = (
      with atomi;
      {
        inherit
          atomiutils
          codemagic-cli-tools
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
          bun
          bundletool
          docker-client
          git
          go-task
          infisical
          jdk17
          jq
          kubeconform
          kubernetes-helm
          kyverno
          pre-commit
          protobuf
          resvg
          ripgrep
          rsync
          shellcheck
          skopeo
          treefmt
          unzip
          yq-go
          zip
          ;
      }
    );

    # ### nix-unstable
    # #### source: main
    nix-unstable = (
      with pkgs-unstable;
      {
        # ### flutter-base-mobile-tools
        # #### source: flutter-base
        inherit
          cocoapods
          fastlane
          flutter
          ;
      }
    );

    # ### flutter-base-android-sdk
    # #### source: flutter-base
    nix-android = {
      androidsdk = androidComposition.androidsdk;
    };

    root = {
      inherit cyanprint;
    };
  };
in
with all;
atomipkgs // nix-2605 // nix-unstable // nix-android // root // { inherit ruby-xcodeproj; }
