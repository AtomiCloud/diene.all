{ treefmt-nix, pkgs, ... }:
let
  fmt = {
    projectRootFile = "flake.nix";

    # ### workspace-formatters
    # #### source: workspace
    programs = {
      actionlint.enable = true;
      nixfmt.enable = true;
      prettier = {
        enable = true;
        excludes = [
          ".claude/skills/vendor/**"
          "Changelog.md"
          "docs/developer/CommitConventions.md"
          "infra/root_chart/**"

          # ### flutter-e4-chart-fmt-excludes
          # #### source: flutter-e4
          # A Helm template is not YAML — prettier errors on the Go-template header.
          # Mirrors the pre-commit treefmt hook's exclude set; both sites are needed
          # so a direct `treefmt` run and the hook agree.
          "infra/primordial_chart/templates/**"
        ];
      };
      shfmt.enable = true;
    };
  };
in
(treefmt-nix.lib.evalModule pkgs fmt).config.build.wrapper
