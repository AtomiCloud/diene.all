{
  atomi,
  pkgs-2605,
  pkgs-unstable,
}:
let
  all = rec {
    go-base = (
      with pkgs-2605;
      {
        deadcode = gotools;
        staticcheck = go-tools;
        inherit
          gofumpt
          golangci-lint
          gotestsum
          govulncheck
          ;
      }
    );

    # ### operator-template
    # #### source: operator-template
    operator = (
      with pkgs-2605;
      {
        controller-gen = kubernetes-controller-tools;
        inherit bun kubebuilder setup-envtest;
        # Offline envtest asset directory: kube-apiserver + etcd + kubectl from the
        # pinned nixpkgs, so `KUBEBUILDER_ASSETS` never triggers a runtime download
        # (M14 cold-runner discipline). Consumed by the shell hook, not on PATH.
        envtest-assets = runCommandLocal "operator-envtest-assets" { } ''
          mkdir -p "$out"
          ln -s ${kubernetes}/bin/kube-apiserver "$out/kube-apiserver"
          ln -s ${etcd}/bin/etcd "$out/etcd"
          ln -s ${kubectl}/bin/kubectl "$out/kubectl"
        '';
      }
    );

    atomipkgs = (
      with atomi;
      {
        inherit
          atomiutils
          cyanprint
          dlint
          # GO-2026-5856: crypto/tls, reachable via adapters/kv, fixed in 1.26.5.
          # The registry exports go 1.26.5 from v5.2.0 onward, so the fix is
          # inherited declaratively here rather than re-pinned by this node.
          go
          go-validator
          infralint
          infrautils
          releaser
          skills-sync
          ;
      }
    );
    nix-unstable = (with pkgs-unstable; { });
    nix-2605 = (
      with pkgs-2605;
      {
        inherit
          actionlint
          git
          go-task
          infisical
          nix
          pre-commit
          shellcheck
          treefmt
          ;
      }
    );
  };
in
with all;
nix-2605 // nix-unstable // atomipkgs // go-base // operator
