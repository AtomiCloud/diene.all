{
  packages,
  formatter,
  pkgs,
  pre-commit-lib,
  env,
}:
let
  bun-tooling = pkgs.stdenvNoCC.mkDerivation {
    pname = "bun-base-pre-commit-tooling";
    version = "1";
    src = builtins.path {
      path = ../.;
      name = "bun-base-pre-commit-tooling-source";
      filter =
        path: type:
        type == "directory"
        || builtins.elem (baseNameOf path) [
          "bun.lock"
          "package.json"
        ];
    };
    nativeBuildInputs = [
      packages.bun
      pkgs.cacert
    ];
    dontConfigure = true;
    buildPhase = ''
      runHook preBuild
      export HOME="$TMPDIR"
      export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      bun install --frozen-lockfile --no-progress --backend=copyfile --cpu='*' --os='*'
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -R node_modules "$out/node_modules"
      runHook postInstall
    '';
    dontFixup = true;
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-Co2uM7abq8evvoljN72mkGlqUeMq8v6+yvG6mCdTASk=";
  };
  bun-tool = name: "${packages.bun}/bin/bun ${bun-tooling}/node_modules/.bin/${name}";
  biome-platform =
    if pkgs.stdenv.hostPlatform.isLinux then
      "linux-${if pkgs.stdenv.hostPlatform.isAarch64 then "arm64" else "x64"}-musl"
    else
      "darwin-${if pkgs.stdenv.hostPlatform.isAarch64 then "arm64" else "x64"}";
  biome-tool = "${bun-tooling}/node_modules/@biomejs/cli-${biome-platform}/biome";
  pre-commit-source = pkgs.runCommand "bun-base-pre-commit-source" { } ''
    mkdir -p "$out"
    cp -R ${../.}/. "$out/"
    ln -s ${bun-tooling}/node_modules "$out/node_modules"
  '';
  validator-runtime = pkgs.buildEnv {
    name = "workspace-validator-runtime";
    paths = [
      packages.bash
      packages.git
      packages.jq
      packages.ripgrep
      packages.yq-go
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.gnused
      # ### nextjs-frontend-validator-runtime
      # #### source: nextjs-frontend
      # The chart-ownership guard renders the Garden app chart per profile.
      packages.kubernetes-helm
    ];
  };
  validator =
    command:
    "${packages.bash}/bin/bash -c 'export PATH=${validator-runtime}/bin; exec ${packages.bash}/bin/bash ${command}'";
  # toolchain-smoke asserts the DECLARED env lists actually provide their binaries.
  envPath = pkgs.lib.makeBinPath (env.system ++ env.main ++ env.lint ++ env.dev);
in
pre-commit-lib.run {
  src = pre-commit-source;

  hooks = {
    treefmt = {
      enable = true;
      package = formatter;
      excludes = [
        "^\\.claude/skills/vendor/"
        "^Changelog\\.md$"
        "^docs/developer/CommitConventions\\.md$"
        "^infra/root_chart/"
      ];
    };

    a-dlint = {
      enable = true;
      name = "dlint";
      entry = "${packages.atomiutils}/bin/bash -c 'PATH=${envPath}:\$PATH ${packages.dlint}/bin/dlint lint'";
      pass_filenames = false;
      language = "system";
    };

    a-infisical = {
      enable = true;
      name = "Secrets scan";
      entry = "${packages.infisical}/bin/infisical scan . -v --redact";
      pass_filenames = false;
      language = "system";
    };

    a-infisical-staged = {
      enable = true;
      name = "Staged secrets scan";
      entry = "${packages.infisical}/bin/infisical scan git-changes --staged -v --redact";
      pass_filenames = false;
      language = "system";
    };

    # The selector is directory-shaped on purpose: every standard under
    # docs/standards/ and every first-level skill trigger is linted, so adding a
    # topic needs no edit here. Vendored skills sit deeper than one level and are
    # ignored again by .markdownlint-cli2.jsonc.
    a-markdownlint = {
      enable = true;
      name = "Markdown lint";
      entry = "${pkgs.markdownlint-cli2}/bin/markdownlint-cli2";
      files = "^(CLAUDE\\.md|README\\.md|docs/standards/.*\\.md|observability/.*\\.md|probes/observability-.*\\.md|\\.claude/skills/[^/]+/SKILL\\.md|\\.claude/skills/(grafana-alert|grafana-alert-set|grafana-dashboards|grafana-runbook|observability-check)/.*\\.md)$";
      pass_filenames = true;
      language = "system";
    };

    a-releaser-commit = {
      enable = true;
      name = "Conventional commit";
      entry = "${packages.releaser}/bin/releaser lint-commit -c release.yaml";
      stages = [ "commit-msg" ];
      pass_filenames = true;
      language = "system";
    };

    a-skills-sync = {
      enable = true;
      name = "Vendored skills";
      entry = "${packages.skills-sync}/bin/skills-sync sync --frozen";
      pass_filenames = false;
      language = "system";
    };

    # -x + SCRIPTDIR: staged-file batching splits scripts from their sources,
    # so ShellCheck must follow source= directives itself.
    a-shellcheck = {
      enable = true;
      name = "Shellcheck";
      entry = "${packages.shellcheck}/bin/shellcheck -x --source-path=SCRIPTDIR";
      files = ".*\\.sh$";
      pass_filenames = true;
      language = "system";
    };

    # ### bun-base-hooks
    # #### source: bun-base
    a-biome = {
      enable = true;
      name = "Biome lint";
      entry = "${biome-tool} lint --no-errors-on-unmatched";
      files = "(^biome\\.json$|\\.(ts|tsx|mts|cts|js|jsx|mjs|cjs)$)";
      pass_filenames = true;
      language = "system";
    };

    a-deadcode = {
      enable = true;
      name = "Knip repository dead code";
      entry = "${bun-tool "knip"} --config knip.json";
      files = "(^package\\.json$|^tsconfig\\.json$|^knip\\.json$|\\.(ts|tsx)$)";
      pass_filenames = false;
      language = "system";
    };

    a-deadcode-production = {
      enable = true;
      name = "Knip production dead code";
      entry = "${bun-tool "knip"} --config knip.production.json";
      files = "(^package\\.json$|^tsconfig\\.json$|^knip\\.production\\.json$|\\.(ts|tsx)$)";
      pass_filenames = false;
      language = "system";
    };

    typecheck = {
      enable = true;
      name = "TypeScript typecheck";
      entry = "${bun-tool "tsc"} --noEmit";
      files = "(^package\\.json$|^tsconfig\\.json$|\\.(ts|tsx|mts|cts)$)";
      pass_filenames = false;
      language = "system";
    };

    # ### nextjs-frontend-hooks
    # #### source: nextjs-frontend
    a-chart-ownership = {
      enable = true;
      name = "Garden app chart ownership";
      entry = validator "scripts/validate/chart-ownership.sh";
      files = "^(infra/garden_app_chart/.*|scripts/validate/chart-ownership\\.sh)$";
      pass_filenames = false;
      language = "system";
    };

    a-i18n-keys = {
      enable = true;
      name = "i18n missing-key lint";
      entry = "${packages.bun}/bin/bun scripts/validate/i18n-keys.ts";
      files = "(^messages/.*\\.json$|^scripts/validate/i18n-keys\\.ts$)";
      pass_filenames = false;
      language = "system";
    };

    a-pure-renderer = {
      enable = true;
      name = "Pure-renderer arch lint";
      entry = "${packages.bun}/bin/bun scripts/validate/pure-renderer.ts";
      files = "^src/app/.*\\.tsx$";
      pass_filenames = false;
      language = "system";
    };

    a-forbidden-runtime = {
      enable = true;
      name = "Forbidden edge runtime";
      entry = "${packages.bun}/bin/bun scripts/validate/forbidden-runtime.ts";
      files = "^src/.*\\.(ts|tsx)$";
      pass_filenames = false;
      language = "system";
    };

    a-rebrand-static = {
      enable = true;
      name = "R21 rebrand static guard";
      entry = "${packages.bun}/bin/bun scripts/validate/rebrand-static.ts";
      files = "(^config/config\\.yaml$|^src/.*\\.(ts|tsx)$)";
      pass_filenames = false;
      language = "system";
    };

    a-wrangler-config = {
      enable = true;
      name = "Wrangler config + ISR bindings";
      entry = "${packages.bun}/bin/bun scripts/validate/wrangler-config.ts";
      files = "(^wrangler\\.toml$|^scripts/validate/wrangler-config\\.ts$)";
      pass_filenames = false;
      language = "system";
    };

    a-deploy-policy = {
      enable = true;
      name = "CloudflareDeploy promotion policy";
      entry = "${packages.bun}/bin/bun scripts/validate/deploy-policy.ts";
      files = "(^scripts/ci/.*\\.sh$|^\\.github/workflows/.*\\.ya?ml$)";
      pass_filenames = false;
      language = "system";
    };

    a-pwa-manifest = {
      enable = true;
      name = "PWA manifest metadata";
      entry = "${packages.bun}/bin/bun scripts/validate/pwa-manifest.ts";
      files = "(^config/config\\.yaml$|^src/app/api/manifest/route\\.ts$)";
      pass_filenames = false;
      language = "system";
    };

    a-config-schema-gen = {
      enable = true;
      name = "Config schema gen-check";
      entry = "${packages.bun}/bin/bun scripts/local/config-schema.ts --check";
      files = "(^config/schema\\.json$|^src/config/.*\\.ts$)";
      pass_filenames = false;
      language = "system";
    };

    # ### shared-hooks
    # #### source: shared
    a-claude-links = {
      enable = true;
      name = "CLAUDE link integrity";
      entry = "${pkgs.coreutils}/bin/env SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt ${pkgs.lychee}/bin/lychee --offline --no-progress CLAUDE.md";
      files = "^(CLAUDE\\.md|docs/standards/.*\\.md)$";
      pass_filenames = false;
      language = "system";
    };
  };
}
