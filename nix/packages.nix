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
          # ### bun-base-packages
          # #### source: bun-base
          bun
          dpkg
          docker-client
          gh
          git
          go
          go-task
          goreleaser
          infisical
          jq
          kubeconform
          kubernetes-helm
          kyverno
          pre-commit
          ripgrep
          rpm
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

    # ### bun-cli-package
    # #### source: bun-cli
    cli =
      let
        bunPkg = pkgs-2605.bun;
        manifest = builtins.fromJSON (builtins.readFile ../package.json);
        cliNames = builtins.attrNames manifest.bin;
        cliName =
          if builtins.length cliNames == 1 then
            builtins.head cliNames
          else
            builtins.throw "bun-cli package requires exactly one package.json bin entry";
        entry = manifest.bin.${cliName};
        src = pkgs.lib.cleanSourceWith {
          src = ../.;
          filter =
            path: _type:
            let
              base = baseNameOf path;
            in
            !(builtins.elem base [
              "node_modules"
              "dist"
              "prebuilt"
              "coverage"
              ".direnv"
              "result"
            ]);
        };
        deps = pkgs.stdenv.mkDerivation {
          pname = "${cliName}-deps";
          version = manifest.version;
          inherit src;
          nativeBuildInputs = [ bunPkg ];
          dontConfigure = true;
          # Production deps only: the compiled binary bundles runtime imports (all pure JS),
          # and excluding devDependencies (notably the platform-specific @biomejs/biome binary)
          # keeps node_modules identical across linux/darwin so one fixed-output hash suffices.
          buildPhase = ''
            export HOME="$TMPDIR"
            bun install --frozen-lockfile --no-progress --production
          '';
          installPhase = ''
            mkdir -p "$out"
            cp -r node_modules "$out/node_modules"
          '';
          dontFixup = true;
          outputHashMode = "recursive";
          outputHashAlgo = "sha256";
          outputHash = "sha256-g0JDKwlzg+Nm5IopmaDl8+2rVe7Lw6cj8+B+B1I73tk=";
        };
      in
      {
        bun-cli = pkgs.stdenv.mkDerivation {
          pname = cliName;
          version = manifest.version;
          inherit src;
          nativeBuildInputs = [ bunPkg ];
          dontConfigure = true;
          buildPhase = ''
            export HOME="$TMPDIR"
            cp -r ${deps}/node_modules ./node_modules
            chmod -R u+w node_modules
            bun build "./${entry}" --compile --outfile "${cliName}"
          '';
          installPhase = ''
            mkdir -p "$out/bin"
            cp "${cliName}" "$out/bin/${cliName}"
          '';
          dontFixup = true;
          meta.mainProgram = cliName;
        };
      };
  };
in
with all;
atomipkgs // nix-2605 // nix-unstable // root // cli
