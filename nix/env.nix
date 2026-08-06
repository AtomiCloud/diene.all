{ pkgs, packages }:
with packages;
{
  dev = [
    git
    go-task
    infisical
    releaser
  ];

  lint = [
    actionlint
    dlint
    infralint
    pre-commit
    shellcheck
    skills-sync
    treefmt

    deadcode
    gofumpt
    golangci-lint
    staticcheck
  ];

  main = [
    cyanprint
    git
    go-task
    infisical
    shellcheck

    go
    gotestsum
    govulncheck
  ];

  releaser = [
    releaser
  ];

  system = [
    atomiutils
    infrautils
  ];
}
