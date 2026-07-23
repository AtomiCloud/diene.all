{ pkgs, packages }:
with packages;
{
  dev = [
    git
  ];

  lint = [
    treefmt
  ];

  main = [
    cyanprint
  ];

  system = [
    atomiutils
  ];
}
