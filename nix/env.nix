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
    pls
  ];

  # ### workspace-lint
  # #### source: workspace
  lint = [
    actionlint
    infralint
    kubeconform
    kubernetes-helm
    kyverno
    pre-commit
    ripgrep
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
    git
    go-task
    infisical
    jq
    kubeconform
    kubernetes-helm
    kyverno
    pls
    packages.releaser
    ripgrep
    shellcheck
    yq-go
  ];

  # ### workspace-releaser-bootstrap
  # #### source: workspace
  releaser = [
    dpkg
    gh
    git
    go
    goreleaser
    packages.releaser
    rpm
  ];

  # ### nix-root-system
  # #### source: main
  system = [
    atomiutils
    infrautils
  ];
}
