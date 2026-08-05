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
    releaser
  ];

  # ### workspace-lint
  # #### source: workspace
  lint = [
    actionlint
    dlint
    infralint
    kubernetes-helm
    pre-commit
    shellcheck
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
    cyanprint
    docker-client
    git
    go-task
    infisical
    jq
    kubernetes-helm
    releaser
    shellcheck
    yq-go
  ];

  # ### workspace-releaser-bootstrap
  # #### source: bun-base
  releaser = [
    releaser
  ];

  # ### nix-root-system
  # #### source: main
  system = [
    atomiutils
    infrautils
  ];
}
