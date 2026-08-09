{
  atomi,
  pkgs-2605,
  pkgs-unstable,
}:
let
  all = rec {
    # ### nix-root
    # #### source: main
    atomipkgs = (
      with atomi;
      {
        inherit
          atomiutils
          cyanprint
          dlint
          # The axis-pure slices, not the `infralint`/`infrautils` aggregates.
          # The aggregates carry the helm axis by CONTENT — infralint ships
          # helm-docs and helmlint, infrautils ships helm — so a node whose
          # defining property is the absence of that axis cannot declare them
          # and still be telling the truth. `infralint-docker` is taken because
          # hadolint and skopeo are invoked here; `infrautils-docker` is not,
          # because `docker-client` below already provides the only binary of
          # it this node uses.
          infralint-core
          infralint-docker
          infrautils-core
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
          nix
          nodejs
          pre-commit
          ripgrep
          rpm
          shellcheck
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
        src = pkgs-2605.lib.cleanSourceWith {
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
        deps = pkgs-2605.stdenv.mkDerivation {
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
          outputHash = "sha256-//nzVPVDGPwgvscaKBcyZhmXXlA6hU3Bt3l6jT5AWH8=";
        };
      in
      {
        bun-cli = pkgs-2605.stdenv.mkDerivation {
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
nix-2605 // nix-unstable // atomipkgs // cli
