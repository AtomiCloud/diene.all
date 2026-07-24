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
    sg
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

    # ### go-base-lint
    # #### source: go-base
    deadcode
    gofumpt
    golangci-lint
    staticcheck
  ];

  # ### workspace-main
  # #### source: workspace
  main = [
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
    ripgrep
    shellcheck
    skopeo
    yq-go

    # ### go-lib-main
    # #### source: go-lib
    gorelease
    zip

    # ### go-base-main
    # #### source: go-base
    go
    gotestsum
    govulncheck
  ];

  # ### workspace-releaser-bootstrap
  # #### source: workspace
  # C2: this bootstrap command is retained until tools/releaser is published at
  # step 2p. Pin node/npm so sg uses the deterministic npm release runtime.
  releaser = [
    nodejs
    releaser
  ];

  # ### nix-root-system
  # #### source: main
  system = [
    atomiutils
    infrautils
  ];
}
