{
  atomi,
  pkgs,
  pkgs-2605,
  pkgs-unstable,
  pkgs-android,
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
