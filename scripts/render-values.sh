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

required_vars=(GIT_ORG GIT_REPO GIT_BRANCH IMAGE_REGISTRY API_HOST RABBITMQ_USERNAME RABBITMQ_PASSWORD)
for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Missing required variable: ${var}"
    exit 1
  fi
done

replace_in_file() {
  local file="$1"
  local find="$2"
  local replace="$3"
  sed -i "s|${find}|${replace}|g" "${file}"
}

echo "Rendering Git repo URLs..."
repo_files=(
  "${ROOT_DIR}/gitops/projects/platform-project.yaml"
  "${ROOT_DIR}/gitops/argocd/root-application.yaml"
  "${ROOT_DIR}/gitops/argocd/apps/apps-workloads.yaml"
  "${ROOT_DIR}/gitops/argocd/apps/chaos.yaml"
  "${ROOT_DIR}/gitops/argocd/apps/operator-self-healer.yaml"
  "${ROOT_DIR}/gitops/argocd/apps/observability-extras.yaml"
  "${ROOT_DIR}/gitops/argocd/apps/platform-security.yaml"
)

for f in "${repo_files[@]}"; do
  replace_in_file "${f}" "https://github.com/YOUR_ORG/YOUR_REPO.git" "https://github.com/${GIT_ORG}/${GIT_REPO}.git"
done

echo "Rendering image repositories..."
replace_in_file "${ROOT_DIR}/apps/api/k8s/deployment.yaml" "ghcr.io/YOUR_ORG/platform-api" "${IMAGE_REGISTRY}/platform-api"
replace_in_file "${ROOT_DIR}/apps/worker/k8s/deployment.yaml" "ghcr.io/YOUR_ORG/queue-worker" "${IMAGE_REGISTRY}/queue-worker"
replace_in_file "${ROOT_DIR}/operator/self-healer/config/manager/manager.yaml" "ghcr.io/YOUR_ORG/self-healer-operator" "${IMAGE_REGISTRY}/self-healer-operator"

echo "Rendering ingress host..."
replace_in_file "${ROOT_DIR}/apps/api/k8s/ingress.yaml" "api.platform.local" "${API_HOST}"

echo "Rendering RabbitMQ credentials..."
replace_in_file "${ROOT_DIR}/apps/rabbitmq.yaml" "appuser" "${RABBITMQ_USERNAME}"
replace_in_file "${ROOT_DIR}/apps/rabbitmq.yaml" "strong-password-change-me" "${RABBITMQ_PASSWORD}"

echo "Rendering operator module imports..."
old_module="github.com/YOUR_ORG/self-healer-operator"
new_module="github.com/${GIT_ORG}/self-healer-operator"
while IFS= read -r file; do
  replace_in_file "${file}" "${old_module}" "${new_module}"
done < <(grep -R -l "${old_module}" "${ROOT_DIR}/operator/self-healer")

echo "Rendering README placeholders..."
replace_in_file "${ROOT_DIR}/README.md" "api.platform.local" "${API_HOST}"
replace_in_file "${ROOT_DIR}/README.md" "YOUR_ORG" "${GIT_ORG}"
replace_in_file "${ROOT_DIR}/README.md" "YOUR_REPO" "${GIT_REPO}"

echo "Done. Run: cd ${ROOT_DIR}/operator/self-healer && go mod tidy && go build ./..."
