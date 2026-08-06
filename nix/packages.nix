{ atomi, pkgs-2605 }:
(with atomi; {
  inherit
    atomiutils
    cyanprint
    dlint
    infralint
    infrautils
    releaser
    skills-sync
    ;
})
// (with pkgs-2605; {
  inherit
    actionlint
    git
    go-task
    infisical
    pre-commit
    shellcheck
    treefmt
    ;
})
