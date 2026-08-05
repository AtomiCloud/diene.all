{ pkgs, packages }:
with packages;
{
  dev = [
    git
    go-task
    infisical
    pls
    releaser
    skopeo
  ];

  lint = [
    actionlint
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

  releaser = [
    releaser
  ];

  system = [
    atomiutils
    infrautils
  ];
}
