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
    # nixos-unstable @ 2026-08-05
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/e72e4f299401a3689d4b3d5fc6496b11db7064eb";
    # nixos-26.05 (Yarara) @ 2026-07-17
    nixpkgs-2605.url = "github:NixOS/nixpkgs/4382ed2b7a6839d4280a9b386db49cbc5907414d";
    # The v4 major is intentionally floating; flake.lock records the exact resolved
    # registry revision. Releaser v2 and skills-sync are supplied by this registry.
    atomipkgs.url = "github:AtomiCloud/nix-registry/v4";
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
