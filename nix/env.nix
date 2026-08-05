{ pkgs, packages }:
with packages;
{
  dev = [
    git
    go-task
    infisical
    sg
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
    ripgrep
    shellcheck
    skopeo
  ];

  # sg is a temporary bootstrap, retained only until the releaser tool is published.
  releaser = [
    sg
  ];

  system = [
    atomiutils
    infrautils
  ];
}
