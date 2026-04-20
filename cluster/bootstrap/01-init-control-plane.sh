#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <control-plane-private-ip>"
  exit 1
fi

CP_IP="$1"

sed "s/CONTROL_PLANE_PRIVATE_IP/${CP_IP}/g" kubeadm-config.yaml >/tmp/kubeadm-config.yaml

sudo kubeadm init --config /tmp/kubeadm-config.yaml --upload-certs

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown "$(id -u)":"$(id -g)" $HOME/.kube/config

echo "Run the generated kubeadm join command on workers."
