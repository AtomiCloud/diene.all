{ packages, ... }:
with packages;
{
  # ### workspace-dev
  # #### source: workspace
  dev = [
    entr
    git
    go-task
    infisical
    jq
    pls
    sg
  ];

  # ### workspace-lint
  # #### source: workspace
  lint = [
    actionlint
    gitlint
    infralint
    pre-commit
    ripgrep
    shellcheck
    treefmt
    yq-go
  ];

  # ### dart-result-main
  # #### source: lib/dart/result
  main = [
    dart
    git
    go-task
    infisical
    jq
    pls
    ripgrep
    shellcheck
    yq-go
  ];

  # ### workspace-releaser-bootstrap
  # #### source: workspace
  releaser = [
    nodejs
    sg
  ];

  # ### nix-root-system
  # #### source: main
  system = [
    atomiutils
    infrautils
  ];
}
