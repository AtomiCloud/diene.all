{ pkgs, packages }:
with packages;
{
  # ### workspace-dev
  # #### source: workspace
  dev = [
    git
    go-task
    infisical
    jq
    packages.releaser
  ];

  # ### workspace-lint
  # #### source: workspace
  lint = [
    actionlint
    dlint
    infralint-core
    pre-commit
    shellcheck
    skills-sync
    treefmt
    yq-go
  ];

  # ### workspace-main
  # #### source: workspace
  main = [
    # ### bun-base-main
    # #### source: bun-base
    bun
    nodejs
    git
    go-task
    infisical
    jq
    packages.releaser
    shellcheck
    yq-go
  ];

  # ### workspace-releaser-bootstrap
  # #### source: bun-base
  releaser = [
    # ### bun-cli-release-tools
    # #### source: bun-cli
    dpkg
    gh
    git
    go
    goreleaser
    rpm
    packages.releaser
  ];

  # ### nix-root-system
  # #### source: main
  system = [
    atomiutils
    infrautils-core
    nix
  ];
}
