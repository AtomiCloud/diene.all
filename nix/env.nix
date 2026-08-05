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

  # C2: sg is retained only until tools/releaser is published at step 2p.
  releaser = [
    sg
  ];

  system = [
    atomiutils
    infrautils
  ];
}
