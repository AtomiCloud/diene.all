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

    # ### dart-lib-packages
    # #### source: dart-lib
    dart-lib-packages = (
      with pkgs-unstable;
      {
        dart = flutter.dart;
      }
    );

    # ### lib-dart-auth-engine-packages
    # #### source: lib/dart/auth-engine
    # FORKED FROM THE PURE-DART FAMILY SHAPE. diene_auth_engine is the first
    # dart lib that needs the FULL Flutter SDK, not just `flutter.dart`:
    # logto_dart_sdk 3.0.0 declares `environment.flutter: '>=1.17.0'` and pulls
    # flutter_secure_storage + flutter_web_auth_2, so `dart pub get` cannot
    # resolve this package's manifest at all ("Flutter users should use
    # `flutter pub` instead of `dart pub`") and its tests need `flutter test`.
    # `dart` above is retained UNCHANGED and still serves every gate that runs
    # under pure Dart (format, and the workspace-root gates). See
    # exec/nodes/lib__dart__auth-engine/evidence/flutter-toolchain-delta.md for
    # the per-invocation justification; api-engine is expected to follow that
    # documented delta or justify a difference against it.
    lib-dart-auth-engine-packages = (
      with pkgs-unstable;
      {
        inherit flutter;
      }
    );

    # ### dart-lib-tools
    # #### source: dart-lib
    dart-lib-tools = (
      with pkgs-2605;
      {
        inherit gitlint;
      }
    );

    root = {
      inherit cyanprint;
    };
  };
in
with all;
atomipkgs
// nix-2605
// nix-unstable
// dart-lib-packages
// dart-lib-tools
# ### lib-dart-auth-engine-packages-merge
# #### source: lib/dart/auth-engine
// lib-dart-auth-engine-packages
// root
