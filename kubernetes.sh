#!/bin/bash
#
# Shortish script to get all Kubernetes components for kubeadm. Following commands might be helpful:
#
# kubeadm init --pod-network-cidr 10.42.0.0/16 --service-cidr 10.43.0.0/16
# cilium install --set encryption.enabled=true --set encryption.type=wireguard --set ipam.mode=kubernetes --set k8s.requireIPv4PodCIDR=true --set k8s.requireIPv6PodCIDR=false
# kubectl taint node $(kubectl get nodes --output name --no-headers) node-role.kubernetes.io/control-plane-
set -e
set -o noglob
set -u

cni_plugins_version=v1.4.0
containerd_version=v1.7.11
cri_tools_version=v1.28.0
runc_version=v1.1.11
kubernetes_version=v1.28.5
release_version=v0.16.4
cilium_cli_version=v0.15.19

cni_plugins()
{
  local version=$1
  mkdir -p /opt/cni/bin
  curl -sSL "https://github.com/containernetworking/plugins/releases/download/$version/cni-plugins-$SYSTEM-$ARCH-$version.tgz" |
    tar xz -C /opt/cni/bin --no-same-owner
  chmod -R 0755 /opt/cni/bin
}

containerd()
{
  local version=$1
  curl -sSL "https://github.com/containerd/containerd/releases/download/$version/containerd-${version//v}-$SYSTEM-$ARCH.tar.gz" |
    tar xz -C /usr/local/bin --no-same-owner --strip-components=1 --wildcards bin/*
  curl -sSLo /etc/systemd/system/containerd.service "https://raw.githubusercontent.com/containerd/containerd/$version/containerd.service"
  mkdir -p /etc/containerd
  cat << EOF > /etc/containerd/config.toml
version = 2
disabled_plugins = []
[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    [plugins."io.containerd.grpc.v1.cri".containerd]
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
            SystemdCgroup = true
EOF
  systemctl daemon-reload
  systemctl enable --now containerd.service
}

cri_tools()
{
  local version=$1
  curl -sSL "https://github.com/kubernetes-sigs/cri-tools/releases/download/$version/crictl-$version-$SYSTEM-$ARCH.tar.gz" |
    tar xz -C /usr/local/bin --no-same-owner
}

runc()
{
  local version=$1
  curl -sSLo /usr/local/bin/runc "https://github.com/opencontainers/runc/releases/download/$version/runc.$ARCH"
  chmod 0755 /usr/local/bin/runc
}

kubernetes()
{
  local version=$1
  local release=$2
  apt-get update --quiet
  apt-get install --assume-yes --no-install-recommends --quiet apparmor conntrack ethtool iptables socat
  curl -sSLo /usr/local/bin/kubeadm "https://dl.k8s.io/release/$version/bin/$SYSTEM/$ARCH/kubeadm"
  curl -sSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/$version/bin/$SYSTEM/$ARCH/kubectl"
  curl -sSLo /usr/local/bin/kubelet "https://dl.k8s.io/release/$version/bin/$SYSTEM/$ARCH/kubelet"
  chmod 0755 /usr/local/bin/kube{adm,ctl,let}
  cat << EOF > /etc/sysctl.d/99-kubernetes.conf
net.ipv4.ip_forward = 1
EOF
  sysctl -p /etc/sysctl.d/99-kubernetes.conf
  cat << EOF > /etc/modules-load.d/kubernetes.conf
br_netfilter
EOF
  modprobe br_netfilter
  cat << EOF > /etc/profile.d/kubernetes.sh
export KUBECONFIG=/etc/kubernetes/admin.conf
source <(kubeadm completion bash)
source <(kubectl completion bash)
alias k=kubectl
complete -o default -F __start_kubectl k
EOF
  curl -sSL "https://raw.githubusercontent.com/kubernetes/release/$release/cmd/krel/templates/latest/kubelet/kubelet.service" | sed "s:/usr/bin:/usr/local/bin:g" > /etc/systemd/system/kubelet.service
  mkdir -p /etc/systemd/system/kubelet.service.d
  curl -sSL "https://raw.githubusercontent.com/kubernetes/release/$release/cmd/krel/templates/latest/kubeadm/10-kubeadm.conf" | sed "s:/usr/bin:/usr/local/bin:g" > /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
  systemctl daemon-reload
  systemctl enable kubelet.service
}

cilium_cli()
{
  local version=$1
  curl -sSL "https://github.com/cilium/cilium-cli/releases/download/$version/cilium-$SYSTEM-$ARCH.tar.gz" |
    tar xz -C /usr/local/bin --no-same-owner
  cat << EOF > /etc/profile.d/cilium-cli.sh
source <(cilium completion bash)
EOF
}

SYSTEM=linux

case $(uname -m) in
  aarch64)
    ARCH=arm64
    ;;
  *)
    echo "unsupported architecture $(uname -m)"
    exit 1
    ;;
esac

cni_plugins $cni_plugins_version
containerd $containerd_version
cri_tools $cri_tools_version
runc $runc_version
kubernetes $kubernetes_version $release_version
cilium_cli $cilium_cli_version

source /etc/profile
