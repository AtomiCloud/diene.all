{
  atomi,
  pkgs-2605,
  pkgs-unstable,
}:
let
  all = rec {
    go-base = (
      with pkgs-2605;
      {
        deadcode = gotools;
        staticcheck = go-tools;
        # GO-2026-5856: crypto/tls, reachable via adapters/kv, fixed in 1.26.5.
        go = pkgs-2605.go.overrideAttrs (
          finalAttrs: _previousAttrs: {
            version = "1.26.5";
            src = pkgs-2605.fetchurl {
              url = "https://go.dev/dl/go${finalAttrs.version}.src.tar.gz";
              hash = "sha256-SVvkvIcXasVnOS5bQRar2YRm0z17SdQedkzMaXay3EI=";
            };
          }
        );
        inherit
          gofumpt
          golangci-lint
          gotestsum
          govulncheck
          ;
      }
    );

    atomipkgs = (
      with atomi;
      {
        inherit
          atomiutils
          cyanprint
          dlint
          go-validator
          infralint
          infrautils
          releaser
          skills-sync
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
          treefmt
          ;
      }
    );

    nix-unstable = (
      with pkgs-unstable;
      {
      }
    );

  };
in
with all;
atomipkgs // nix-2605 // nix-unstable // go-base
