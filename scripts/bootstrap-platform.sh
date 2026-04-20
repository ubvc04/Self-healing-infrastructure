#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${1:-${ROOT_DIR}/config/platform.env}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing env file: ${ENV_FILE}"
  echo "Copy ${ROOT_DIR}/config/platform.env.example to ${ROOT_DIR}/config/platform.env and set values."
  exit 1
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

required_vars=(SSH_PRIVATE_KEY_PATH)
for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Missing required variable: ${var}"
    exit 1
  fi
done

if [[ -n "${SSH_INGRESS_CIDR:-}" ]]; then
  echo "Using SSH_INGRESS_CIDR from env: ${SSH_INGRESS_CIDR}"
fi

for cmd in terraform jq ssh scp; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing command: ${cmd}"
    exit 1
  fi
done

if [[ ! -f "${SSH_PRIVATE_KEY_PATH/#\~/$HOME}" ]]; then
  echo "SSH key does not exist at: ${SSH_PRIVATE_KEY_PATH}"
  exit 1
fi

echo "[1/6] Rendering project values"
"${ROOT_DIR}/scripts/render-values.sh" "${ENV_FILE}"

echo "[2/6] Provisioning AWS infrastructure"
pushd "${ROOT_DIR}/infra/terraform/aws" >/dev/null
terraform init
terraform apply -auto-approve

CP_PUBLIC_IP="$(terraform output -raw control_plane_public_ip)"
CP_PRIVATE_IP="$(terraform output -json private_ips | jq -r '."control-plane"')"
mapfile -t WORKER_PUBLIC_IPS < <(terraform output -json worker_public_ips | jq -r '.[]')
popd >/dev/null

SSH_KEY="${SSH_PRIVATE_KEY_PATH/#\~/$HOME}"
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${SSH_KEY}")

ALL_NODES=("${CP_PUBLIC_IP}" "${WORKER_PUBLIC_IPS[@]}")

echo "[3/6] Syncing cluster bootstrap scripts to nodes"
for node in "${ALL_NODES[@]}"; do
  scp "${SSH_OPTS[@]}" -r "${ROOT_DIR}/cluster" "ubuntu@${node}:~/platform"
done

echo "[4/6] Initializing control plane"
ssh "${SSH_OPTS[@]}" "ubuntu@${CP_PUBLIC_IP}" "cd ~/platform/bootstrap && bash 01-init-control-plane.sh ${CP_PRIVATE_IP} && bash 02-install-cni-cilium.sh && bash 03-install-addons.sh"
JOIN_CMD="$(ssh "${SSH_OPTS[@]}" "ubuntu@${CP_PUBLIC_IP}" "cd ~/platform/bootstrap && bash 04-generate-join-command.sh")"

echo "[5/6] Joining worker nodes"
for worker in "${WORKER_PUBLIC_IPS[@]}"; do
  ssh "${SSH_OPTS[@]}" "ubuntu@${worker}" "cd ~/platform/bootstrap && bash 05-join-worker.sh '${JOIN_CMD}'"
done

echo "[6/6] Cluster bootstrap complete"
echo "Control plane: ${CP_PUBLIC_IP}"
echo "Run to verify from control-plane host:"
echo "  kubectl get nodes -o wide"
echo "  kubectl get pods -A"
echo "Then install GitOps stack from the control-plane host or your admin workstation."
