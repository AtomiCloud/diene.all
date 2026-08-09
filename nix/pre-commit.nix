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
    outputHash = "sha256-rAk5chYo8iCSowuIrdOc9jX7THNpgFd2kezoVTMWdcw=";
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
  # Kept for the bun-consumer validator hooks below, which the parent's dlint
  # migration does not cover. ripgrep left the workspace package block when the
  # registry started bundling it, so atomiutils supplies rg on the wrapper PATH
  # rather than being merged into the buildEnv (which would collide).
  validator-runtime = pkgs.buildEnv {
    name = "workspace-validator-runtime";
    paths = [
      packages.bash
      packages.bun
      packages.git
      packages.jq
      packages.yq-go
      pkgs.coreutils
      pkgs.diffutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.gnused
    ];
  };
  validator =
    command:
    "${packages.bash}/bin/bash -c 'export PATH=${validator-runtime}/bin:${packages.atomiutils}/bin; exec ${packages.bash}/bin/bash ${command}'";
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
        "^infra/primordial_chart/"
        "^infra/root_chart/"
        "^schemas/"
      ];
    };

    a-dlint = {
      enable = true;
      name = "dlint";
      entry = "${packages.atomiutils}/bin/bash -c 'PATH=${envPath}:\$PATH ${packages.dlint}/bin/dlint lint'";
      pass_filenames = false;
      language = "system";
    };

    a-helm-lint = {
      enable = true;
      name = "Helm lint";
      entry = "${packages.infrautils}/bin/helm lint infra/root_chart";
      files = "^infra/root_chart/.*";
      pass_filenames = false;
      language = "system";
    };

    # ### bun-consumer-primordial-chart-hooks
    # #### source: bun-consumer
    a-helm-docs-primordial = {
      enable = true;
      name = "Primordial Helm docs";
      entry = "${packages.infralint}/bin/helm-docs --chart-search-root infra/primordial_chart";
      files = "^infra/primordial_chart/.*";
      pass_filenames = false;
      language = "system";
    };

    a-helm-lint-primordial = {
      enable = true;
      name = "Primordial Helm lint";
      entry = "${packages.kubernetes-helm}/bin/helm lint infra/primordial_chart";
      files = "^infra/primordial_chart/.*";
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
    #
    # ### observability-markdown
    # #### source: observability
    # The observability payload adds markdown the directory shape does not reach:
    # the top-level observability/ dir, the probe add-back checklist, and the
    # grafana / observability-check skill templates, which sit one level deeper
    # than SKILL.md. They were linted before the bun-base cascade and stay linted.
    a-markdownlint = {
      enable = true;
      name = "Markdown lint";
      entry = "${pkgs.markdownlint-cli2}/bin/markdownlint-cli2";
      files = "^(CLAUDE\\.md|README\\.md|docs/standards/.*\\.md|\\.claude/skills/[^/]+/SKILL\\.md|observability/.*\\.md|probes/observability-.*\\.md|\\.claude/skills/(grafana-alert|grafana-alert-set|grafana-dashboards|grafana-runbook|observability-check)/.*\\.md)$";
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

    # ### bun-consumer-hooks
    # #### source: bun-consumer
    a-constants-sync = {
      enable = true;
      name = "Keyed adapter constants sync";
      entry = validator "scripts/validate/constants-sync.sh";
      files = "^(config/settings\\.yaml|src/config/constants\\.ts)$";
      pass_filenames = false;
      language = "system";
    };

    a-rebrand-config = {
      enable = true;
      name = "Config-driven rebrand guard";
      entry = validator "scripts/validate/rebrand.sh";
      files = "^(config/settings\\.yaml|src/.*\\.ts)$";
      pass_filenames = false;
      language = "system";
    };

    a-schema-drift = {
      enable = true;
      name = "Generated config schema drift";
      entry = validator "scripts/validate/schema-drift.sh";
      files = "^(config/.*\\.yaml|schemas/.*\\.json|src/config/.*\\.ts)$";
      pass_filenames = false;
      language = "system";
    };

  };
}
