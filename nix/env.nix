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
    pre-commit
    shellcheck
    treefmt
  ];

  main = [
    cyanprint
    git
    go-task
    infisical
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
