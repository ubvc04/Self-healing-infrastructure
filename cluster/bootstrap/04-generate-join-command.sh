#!/usr/bin/env bash
set -euo pipefail

kubeadm token create --print-join-command
