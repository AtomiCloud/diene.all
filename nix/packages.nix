{
  atomi,
  pkgs,
  pkgs-2605,
  pkgs-unstable,
  releaser-pkg,
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
    atomipkgs = (
      with atomi;
      {
        inherit
          atomiutils
          infralint
          infrautils
          ;
      }
    );

    nix-2605 = (
      with pkgs-2605;
      {
        inherit
          actionlint
          git
          go-task
          infisical
          pre-commit
          shellcheck
          skopeo
          treefmt
          ;
      }
    );

    nix-unstable = (
      with pkgs-unstable;
      {
      }
    );

    # The releaser is its own flake, not a registry bundle member, so it gets its
    # own group rather than joining `atomipkgs`. It replaces the temporary gitlint
    # bootstrap this toolchain carried while the releaser was unavailable here,
    # which is dropped from the registry group above.
    #
    # That bootstrap's own name is deliberately absent from this file: binary
    # smoke refuses if it appears in this file or in nix/env.nix, and a comment
    # naming it would turn the guard red on a tree that is correct. The removal is
    # explained where the guard lives, not where the guard reads.
    releaser-pkgs = {
      releaser = releaser-pkg;
    };

    root = {
      inherit cyanprint;
    };
  };
in
with all;
atomipkgs // nix-2605 // nix-unstable // releaser-pkgs // root
