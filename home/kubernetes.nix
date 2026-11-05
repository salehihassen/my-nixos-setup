{ pkgs, ... }:

# Local k3d clusters and remote cluster administration. k3d needs a Docker
# daemon the user can reach; the host provides it, not this module.
{
  home.packages = with pkgs; [
    kubectl
    k9s
    k3d
    kubernetes-helm
    kubectx # also provides kubens
    stern # tail logs across pods
  ];
}
