{
  pkgs,
  packages,
  env,
  shellHook,
}:
let
  # ### operator-template-shellhook
  # #### source: operator-template
  # Point envtest at the offline nix asset directory (kube-apiserver/etcd/kubectl)
  # so int-tier envtest suites never download binaries at test time (M14).
  shellHookWithEnvtest = shellHook + ''
    export KUBEBUILDER_ASSETS="${packages.envtest-assets}"
  '';
in
with env;
{
  # ### workspace-cd
  # #### source: workspace
  cd = pkgs.mkShell {
    buildInputs = main ++ system;
    shellHook = shellHookWithEnvtest;
  };

  # ### workspace-ci
  # #### source: workspace
  ci = pkgs.mkShell {
    buildInputs = lint ++ main ++ system;
    shellHook = shellHookWithEnvtest;
  };

  # ### nix-root-default
  # #### source: main
  default = pkgs.mkShell {
    buildInputs = system ++ main ++ lint ++ dev;
    shellHook = shellHookWithEnvtest;
  };

  # ### workspace-releaser
  # #### source: workspace
  releaser = pkgs.mkShell {
    buildInputs = lint ++ main ++ releaser ++ system;
    shellHook = shellHookWithEnvtest;
  };
}
