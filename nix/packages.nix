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
          # GO-2026-5856: crypto/tls, reachable via adapters/kv, fixed in 1.26.5.
          # The registry exports go 1.26.5 from v5.2.0 onward, so the fix is
          # inherited declaratively here rather than re-pinned by this node.
          go
          go-validator
          infralint
          infrautils
          releaser
          skills-sync
          ;
      }
    );
    nix-unstable = (with pkgs-unstable; { });
    nix-2605 = (
      with pkgs-2605;
      {
        inherit
          actionlint
          git
          go-task
          infisical
          nix
          pre-commit
          shellcheck
          treefmt
          ;
      }
    );
  };
in
with all;
nix-2605 // nix-unstable // atomipkgs // go-base
