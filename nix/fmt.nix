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
          # Digest-authenticated C0 projections: their exact bytes are pinned by
          # test/fixtures/c0/SHA256SUMS, so any reformat is a drift failure. The
          # release's own .prettierignore anchors these paths at the repository
          # root, which does not reach a workspace member, so the member-scoped
          # paths are excluded here instead (same shape as diene_result and
          # diene_interfaces).
          "packages/diene_problems/test/fixtures/c0/catalog-entry.json"
          "packages/diene_problems/test/fixtures/c0/envelope.json"
          "packages/diene_problems/test/fixtures/c0/type-uri.json"
        ];
      };
      shfmt.enable = true;
    };
  };
in
(treefmt-nix.lib.evalModule pkgs fmt).config.build.wrapper
