{ pkgs, packages }:
with packages;
{
  dev = [
    git
    go-task
    infisical
    pls
    skopeo
  ];

  lint = [
    actionlint
    dn-inspect
    dotnetlint
    infralint
    kubeconform
    kyverno
    pre-commit
    ripgrep
    shellcheck
    treefmt
  ];

  main = [
    cyanprint
    docker-client
    dotnet-sdk_10
    git
    go-task
    infisical
    kubeconform
    kyverno
    pls
    ripgrep
    shellcheck
    skopeo
    packages.releaser
    xmlstarlet
  ];

  releaser = [
    packages.releaser
  ];

  system = [
    atomiutils
    infrautils
  ];
}
