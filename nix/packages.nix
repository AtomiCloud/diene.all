{
  atomi,
  pkgs,
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
          infralint
          infrautils
          pls
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
          dpkg
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
          treefmt
          yq-go
          ;
      }
    );

    nix-unstable = (with pkgs-unstable; { });

    # ### releaser-package
    # #### source: releaser
    cli =
      let
        bunPkg = pkgs-2605.bun;
        manifest = builtins.fromJSON (builtins.readFile ../package.json);
        cliNames = builtins.attrNames manifest.bin;
        cliName =
          if builtins.length cliNames == 1 then
            builtins.head cliNames
          else
            builtins.throw "CLI package requires exactly one package.json bin entry";
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
          outputHash = "sha256-nocInNOHwiD/Nh6pkU/VjwFarXrXNi0fQfScpO2ml4Q=";
        };
      in
      {
        releaser = pkgs.stdenv.mkDerivation {
          pname = cliName;
          version = manifest.version;
          inherit src;
          nativeBuildInputs = [ bunPkg ];
          dontConfigure = true;
          buildPhase = ''
            export HOME="$TMPDIR"
            cp -r --no-preserve=mode ${deps}/node_modules ./node_modules
            bun build "./${entry}" --compile --outfile "${cliName}"
          '';
          installPhase = ''
            install -Dm755 "${cliName}" "$out/bin/${cliName}"
          '';
          dontFixup = true;
          meta.mainProgram = cliName;
        };
      };
  };
in
with all;
atomipkgs // nix-2605 // nix-unstable // cli
