{
  atomi,
  pkgs-2605,
  pkgs-unstable,
  pkgs-android,
}:
let
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
          cyanprint
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
          bun
          bundletool
          git
          go-task
          infisical
          jdk17
          jq
          nix
          pre-commit
          protobuf
          resvg
          ripgrep
          rsync
          shellcheck
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
  };
in
with all;
nix-2605 // nix-unstable // atomipkgs // nix-android // { inherit ruby-xcodeproj; }
