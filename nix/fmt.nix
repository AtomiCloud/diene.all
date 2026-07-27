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
          # ### lib-dart-auth-engine-formatter
          # #### source: lib/dart/auth-engine
          # The C0 identity projection is a DIGEST-BOUND artifact: the
          # conformance suite refuses to run unless the file's sha256 equals the
          # value in test/fixtures/c0/SHA256SUMS, and both are written together
          # by tool/gen_c0_projection.dart. Any formatter touching it breaks that
          # binding, and the failure reads exactly like real evidence corruption.
          #
          # `contracts/c0/**` is protected from the same hazard by the
          # digest-locked root `.prettierignore` (pinned by RELEASE.json
          # formatterPolicy.sha256). That file CANNOT cover this path — its
          # entries anchor at the repository root, not inside a workspace member
          # — and it must not be edited, so the exclusion belongs here instead.
          "packages/diene_auth_engine/test/fixtures/c0/**"
        ];
      };
      shfmt.enable = true;
    };
  };
in
(treefmt-nix.lib.evalModule pkgs fmt).config.build.wrapper
