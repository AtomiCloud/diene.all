{ pkgs, packages }:
with packages;
{
  dev = [
    git
    go-task
    infisical
    pls
    sg
    skopeo
  ];

  lint = [
    actionlint
    dn-inspect
    dotnetlint
    gitlint
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
  ];

  # C2: sg is retained only until tools/releaser is published at step 2p.
  releaser = [
    sg
  ];

  system = [
    atomiutils
    infrautils
  ];
}
