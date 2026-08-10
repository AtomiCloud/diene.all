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
    infralint-core
    # ### nextjs-frontend-lint
    # #### source: nextjs-frontend
    kubernetes-helm
    pre-commit
    ripgrep
    shellcheck
    skills-sync
    treefmt
    yq-go
  ];

  # ### workspace-main
  # #### source: workspace
  main = [
    # ### nextjs-frontend-main
    # #### source: nextjs-frontend
    nodejs
    # ### nextjs-frontend-main
    # #### source: nextjs-frontend
    kubernetes-helm
    ripgrep
    # ### bun-base-main
    # #### source: bun-base
    bun
    nodejs
    cyanprint
    git
    go-task
    infisical
    jq
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
    infrautils-core
    nix
  ];
}
