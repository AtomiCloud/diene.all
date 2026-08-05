{
  inputs = {
    # util
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";

    # registry
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-2605.url = "github:NixOS/nixpkgs/4382ed2b7a6839d4280a9b386db49cbc5907414d";
    # This is a revision because the registry release containing dlint and the
    # shared Go validator has not been tagged yet. Move to that tag when it ships.
    atomipkgs.url = "github:AtomiCloud/nix-registry/df887f719f64e4b53aa7171779b2f0178ac6f667";
  };
  outputs =
    {
      self,

      # utils
      flake-utils,
      treefmt-nix,
      pre-commit-hooks,

      # registries
      atomipkgs,
      nixpkgs-2605,
      nixpkgs-unstable,

    }@inputs:
    (flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs-2605 = nixpkgs-2605.legacyPackages.${system};
        pkgs-unstable = nixpkgs-unstable.legacyPackages.${system};
        atomi = atomipkgs.packages.${system};
        pre-commit-lib = pre-commit-hooks.lib.${system};
      in
      let
        pkgs = pkgs-2605;
      in
      with rec {
        pre-commit = import ./nix/pre-commit.nix {
          inherit
            packages
            pkgs
            pre-commit-lib
            formatter
            ;
        };
        formatter = import ./nix/fmt.nix {
          inherit treefmt-nix pkgs;
        };
        packages = import ./nix/packages.nix {
          inherit
            pkgs
            pkgs-2605
            pkgs-unstable
            atomi
            ;
        };
        env = import ./nix/env.nix {
          inherit pkgs packages;
        };
        devShells = import ./nix/shells.nix {
          inherit pkgs env packages;
          shellHook = checks.pre-commit-check.shellHook;
        };
        checks = {
          pre-commit-check = pre-commit;
          format = formatter;
        };
      };
      {
        inherit
          checks
          formatter
          packages
          devShells
          ;
      }
    ));

}
