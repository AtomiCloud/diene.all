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
    # As of the last check `v3`, `v3.14` and `v3.14.0` all resolve to
    # 8bf1f2744b0551ad6779a49d02a1df36b5ff2853; the first two are retargeted at
    # every release, so only the three-part tag stays put.
    atomipkgs.url = "github:AtomiCloud/nix-registry/v3.14.0";
    # NOTHING VALIDATES THIS. releaser v1.0.0 = the commit below.
    releaser = {
      url = "github:AtomiCloud/releaser/3200bdd95a0fdd8f43f9905faa8c85afe4595d1f";
      inputs.atomipkgs.follows = "atomipkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.nixpkgs-2605.follows = "nixpkgs-2605";
      inputs.nixpkgs-unstable.follows = "nixpkgs-unstable";
      inputs.pre-commit-hooks.follows = "pre-commit-hooks";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };
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
      releaser,

    }@inputs:
    (flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs-2605 = nixpkgs-2605.legacyPackages.${system};
        pkgs-unstable = nixpkgs-unstable.legacyPackages.${system};
        atomi = atomipkgs.packages.${system};
        releaser-pkg = releaser.packages.${system}.releaser;
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
            releaser-pkg
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
