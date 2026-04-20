#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 '<kubeadm join ...>'"
  exit 1
fi

sudo $1
