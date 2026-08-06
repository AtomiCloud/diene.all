{ pkgs, packages }:
with packages;
{
  # ### workspace-dev
  # #### source: workspace
  dev = [
    git
    go-task
    infisical
    releaser
    jq
    skopeo
  ];

  # ### workspace-lint
  # #### source: workspace
  lint = [
    actionlint
    dlint
    infralint
    kubeconform
    kubernetes-helm
    kyverno
    pre-commit
    ripgrep
    shellcheck
    skills-sync
    treefmt
    yq-go

    # ### dotnet-base-lint
    # #### source: dotnet-base
    dn-inspect
    dotnetlint
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
    ripgrep
    shellcheck
    skopeo
    yq-go

    # ### dotnet-base-main
    # #### source: dotnet-base
    dotnet-sdk_10
    packages.releaser
    xmlstarlet
  ];

  # ### workspace-releaser-bootstrap
  # #### source: dotnet-base
  releaser = [
    packages.releaser
  ];

  # ### nix-root-system
  # #### source: main
  system = [
    atomiutils
    infrautils
  ];
}
