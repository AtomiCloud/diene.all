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
        cliName = builtins.head (builtins.attrNames manifest.bin);
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
          buildPhase = ''
            export HOME="$TMPDIR"
            bun install --frozen-lockfile --no-progress
          '';
          installPhase = ''
            mkdir -p "$out"
            cp -r node_modules "$out/node_modules"
          '';
          dontFixup = true;
          outputHashMode = "recursive";
          outputHashAlgo = "sha256";
          outputHash = "sha256-SpnLtJvmEIfnzXhU8odLN4Mj/2ap/TgxiX3VSOuDNnQ=";
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
