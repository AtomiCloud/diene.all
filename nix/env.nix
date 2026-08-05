{ pkgs, packages }:
with packages;
{
  dev = [
    git
    go-task
    infisical
    pls
    releaser
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
    pls
    shellcheck
  ];

  releaser = [
    releaser
  ];

  system = [
    atomiutils
    infrautils
  ];
}
