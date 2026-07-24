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

    # ### dotnet-base-lint
    # #### source: dotnet-base
    dn-inspect
    dotnetlint
    gitlint
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
    unzip
    xmlstarlet
    yq-go

    # ### dotnet-base-main
    # #### source: dotnet-base
    dotnet-sdk_10
  ];

  # ### workspace-releaser-bootstrap
  # #### source: workspace
  # C2: sg is retained only until tools/releaser is published at step 2p.
  releaser = [
    sg
  ];

  # ### nix-root-system
  # #### source: main
  system = [
    atomiutils
    infrautils
  ];
}
