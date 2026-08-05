{
  packages,
  formatter,
  pkgs,
  pre-commit-lib,
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
  validator-runtime = pkgs.buildEnv {
    name = "workspace-validator-runtime";
    # atomiutils supplies bash/jq/yq plus the coreutils/find/grep/sed binaries the
    # validators call - and, since registry v3.12.0, rg as well - so declaring any
    # of those separately would duplicate the bundle and collide with it in this
    # buildEnv. That is not a prediction: while v3.12.0 was landing, a standalone
    # nixpkgs ripgrep alongside the bundle failed this very buildEnv with
    # "conflicting subpath ... /bin/rg". git is the only entry left that the
    # bundle does not already carry.
    paths = [
      packages.atomiutils
      packages.git
    ];
  };
  validator =
    command:
    "${packages.atomiutils}/bin/bash -c 'export PATH=${validator-runtime}/bin; exec ${packages.atomiutils}/bin/bash ${command}'";
  # One hook, several invocations of the same validator: identical runtime PATH,
  # stopping at the first non-zero exit so the reported failure is the gate that
  # actually failed. Used where one validator script owns several modes and the
  # modes do not warrant separate hooks.
  validators =
    commands:
    "${packages.atomiutils}/bin/bash -c 'export PATH=${validator-runtime}/bin; ${
      builtins.concatStringsSep " && " (
        map (command: "${packages.atomiutils}/bin/bash ${command}") commands
      )
    }'";
  dlint = check: "${packages.dlint}/bin/dlint ${check}";
  dlints =
    checks:
    "${packages.atomiutils}/bin/bash -c '${
      builtins.concatStringsSep " && " (map (check: "${packages.dlint}/bin/dlint ${check}") checks)
    }'";
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

    a-action-pins = {
      enable = true;
      name = "Action pins";
      entry = dlints [
        "action-pins trusted"
        "action-pins non-trusted"
      ];
      files = "^(\\.github/workflows/.*\\.ya?ml|config/action-trust\\.json)$";
      pass_filenames = false;
      language = "system";
    };

    a-enforce-exec = {
      enable = true;
      name = "Executable shell scripts";
      entry = dlint "exec-bits";
      files = ".*\\.sh$";
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
      files = "^(CLAUDE\\.md|README\\.md|docs/standards/.*\\.md|\\.claude/skills/[^/]+/SKILL\\.md)$";
      pass_filenames = true;
      language = "system";
    };

    a-releaser-commit = {
      enable = true;
      name = "Conventional commit";
      entry = "${packages.releaser}/bin/releaser lint-commit -c atomi_release.yaml";
      stages = [ "commit-msg" ];
      pass_filenames = true;
      language = "system";
    };

    # Source following belongs to the gate itself, not to an ambient SHELLCHECK_OPTS:
    # pre-commit partitions the staged files, so a script and the script it sources
    # routinely land in different batches, and bare ShellCheck then raises SC1091 on
    # healthy sources. `-x` follows a declared `source=`, and `--source-path=SCRIPTDIR`
    # adds the checked script's own directory so script-relative directives resolve
    # too, on top of the repository-root-relative ones the working directory already
    # covers. Findings from the sourced file stay out of the report (that would need
    # `-a`), so the gate gains resolution without gaining noise.
    a-shellcheck = {
      enable = true;
      name = "Shellcheck";
      entry = "${packages.shellcheck}/bin/shellcheck -x --source-path=SCRIPTDIR";
      files = ".*\\.sh$";
      pass_filenames = true;
      language = "system";
    };

    a-skills-freshness = {
      enable = true;
      name = "Vendored skills freshness";
      entry = dlint "skills-fresh";
      pass_filenames = false;
      language = "system";
    };

    a-workflows = {
      enable = true;
      name = "Workflow wiring and release policy";
      entry = "${packages.atomiutils}/bin/bash -c '${packages.dlint}/bin/dlint ci-wiring && ( export PATH=${validator-runtime}/bin; ${packages.atomiutils}/bin/bash scripts/validate/workflows.sh release-trigger && ${packages.atomiutils}/bin/bash scripts/validate/workflows.sh release-concurrency )'";
      files = "^\\.github/workflows/.*\\.ya?ml$";
      pass_filenames = false;
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
  };
}
