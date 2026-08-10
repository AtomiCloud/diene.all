{
  # ### workspace-flake
  # #### source: workspace
  inputs = {
    # util
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";

    # registry
    #
    # Every nixpkgs input is pinned to an EXACT COMMIT, never to a channel name.
    # A channel branch moves under us, so a floating ref makes the same tree
    # build differently on two days. Moving a pin is a deliberate human-cadence
    # action, taken on purpose by a person: drift away from upstream is reported
    # separately, on its own regular cadence, and that report never bumps
    # anything itself.
    #
    # On THIS node the rule is enforced: scripts/validate/nixpkgs-pin.sh checks the
    # nixpkgs-2605 revision against nix/snapshots/nixpkgs.json, checks flake.lock
    # agrees, refuses a floating nixos-26.05 input, and requires the registry tag
    # below to be a three-part one. The parent deleted that gate by owner ruling on
    # 2026-08-05 and its copy of this comment says nothing validates it - that is
    # true there and false here, so the wording is deliberately not the parent's.
    #
    # nixos-unstable @ 2026-08-06
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/b7c2ada94fe99c15b0dbcf4d11fd7850b957a436";
    # nixos-26.05 (Yarara) @ 2026-08-06
    nixpkgs-2605.url = "github:NixOS/nixpkgs/445d861c6d31b4af0c79d8d4be2331f762a361d7";
    # The v5 major is intentionally floating; flake.lock records the exact resolved
    # registry revision. Releaser v2 and skills-sync are supplied by this registry.
    atomipkgs.url = "github:AtomiCloud/nix-registry/v5";
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
            env
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
