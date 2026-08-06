{
  atomi,
  pkgs-2605,
  pkgs-unstable,
}:
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
// (with pkgs-unstable; { })
