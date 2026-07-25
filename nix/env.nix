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
    skopeo
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
    cyanprint
    docker-client
    git
    go-task
    infisical
    jq
    kubeconform
    kubernetes-helm
    kyverno
    pls
    releaser
    ripgrep
    shellcheck
    skopeo
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
    releaser
  ];

  # ### nix-root-system
  # #### source: main
  system = [
    atomiutils
    infrautils
  ];
}
