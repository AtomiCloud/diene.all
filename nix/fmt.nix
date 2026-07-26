{ treefmt-nix, pkgs, ... }:
let
  fmt = {
    projectRootFile = "flake.nix";

    # ### workspace-formatters
    # #### source: workspace
    programs = {
      actionlint.enable = true;
      # ### go-base-formatter
      # #### source: go-base
      gofumpt.enable = true;
      nixfmt.enable = true;
      prettier = {
        enable = true;
        excludes = [
          ".claude/skills/vendor/**"
          "Changelog.md"
          "docs/developer/CommitConventions.md"
          "infra/root_chart/**"

          # ### go-consumer-prettier-excludes
          # #### source: go-consumer
          # Generated chart and schema surfaces stay byte-owned by their generators
          # (helm-docs READMEs, the problems export, schema-gen output); prettier must not
          # fight them. Mirrors the pre-commit treefmt hook's exclude set.
          "infra/primordial_chart/**"
          "schemas/**"
        ];
      };
      shfmt.enable = true;
    };
  };
in
(treefmt-nix.lib.evalModule pkgs fmt).config.build.wrapper
