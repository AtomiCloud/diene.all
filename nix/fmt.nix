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

          # ### bun-consumer-prettier-excludes
          # #### source: bun-consumer
          # Helm templates are Go templates, not YAML — prettier cannot parse them.
          # Only `templates/**` is excluded: the primordial chart's values, schema,
          # README, and CRD fixtures are ordinary YAML/JSON/Markdown and stay
          # formatted. The app chart is already covered by the workspace entry above.
          "infra/primordial_chart/templates/**"
        ];
      };
      shfmt.enable = true;
    };
  };
in
(treefmt-nix.lib.evalModule pkgs fmt).config.build.wrapper
