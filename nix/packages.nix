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

    # ### lib-dart-e2e-packages
    # #### source: lib/dart/e2e
    # FORKED FROM THE PURE-DART FAMILY SHAPE, following the precedent auth-engine
    # set and api-engine followed. diene_e2e needs the FULL Flutter SDK, not just
    # `flutter.dart`, because it is the family VERSION TRAIN: it depends on all
    # seven members, two of which (diene_auth_engine, diene_api_engine) declare
    # `flutter: '>=3.24.0'`. Measured rather than reasoned — `dart pub get` on
    # this manifest refuses with "Flutter users should use `flutter pub` instead
    # of `dart pub`", and `flutter pub get` in the inherited dart-only shell dies
    # with "command 'flutter' not found on PATH". So `flutter pub get` /
    # `flutter test` are the only invocations that can resolve and run this
    # member. `dart` above is retained UNCHANGED and still serves every
    # pure-Dart gate (notably `dart format`, which is SDK-agnostic).
    lib-dart-e2e-packages = (
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
# ### lib-dart-e2e-packages-merge
# #### source: lib/dart/e2e
// lib-dart-e2e-packages
// root
