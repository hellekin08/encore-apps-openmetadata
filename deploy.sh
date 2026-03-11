#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_NAME=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      ENV_NAME="$2"
      shift 2
      ;;
    -*)
      echo "ERROR: Unknown option: $1"
      exit 1
      ;;
    *)
      echo "ERROR: Unexpected positional argument: $1"
      echo "Usage: $0 --env <environment>"
      exit 1
      ;;
  esac
done

if [[ -z "$ENV_NAME" ]]; then
  echo "Usage: $0 --env <environment>"
  echo "Example: $0 --env dev"
  exit 1
fi

APP_NAME="openmetadata"
OVERLAY_DIR="${SCRIPT_DIR}/openmetadata/app/overlays/${ENV_NAME}"
OVERLAY_KUSTOMIZATION_FILE="${OVERLAY_DIR}/kustomization.yaml"
CLUSTER_DIR="${SCRIPT_DIR}/openmetadata/clusters/${ENV_NAME}"
GIT_REPO_FILE="${CLUSTER_DIR}/gitrepository.yaml"
KUSTOMIZATION_FILE="${CLUSTER_DIR}/${APP_NAME}.yaml"

for f in "$OVERLAY_KUSTOMIZATION_FILE" "$GIT_REPO_FILE" "$KUSTOMIZATION_FILE"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: Required file not found: $f"
    exit 1
  fi
done

TARGET_NS=$(grep '^namespace:' "$OVERLAY_KUSTOMIZATION_FILE" | awk '{print $2}')
if [[ -z "$TARGET_NS" ]]; then
  echo "ERROR: Could not extract namespace from $OVERLAY_KUSTOMIZATION_FILE"
  exit 1
fi

echo "=== Deploying app: ${APP_NAME} (env: ${ENV_NAME}) ==="
echo "    Target namespace: ${TARGET_NS}"

if kubectl get namespace "$TARGET_NS" &>/dev/null; then
  echo "[OK] Namespace '${TARGET_NS}' already exists"
else
  echo "[..] Namespace '${TARGET_NS}' not found"
  echo "Create the namespace first, then rerun this script."
  exit 1
fi

SECRET_NAME=$(grep 'secretRef' -A1 "$GIT_REPO_FILE" | grep 'name:' | awk '{print $2}')
if [[ -n "$SECRET_NAME" ]]; then
  if kubectl get secret "$SECRET_NAME" -n "$TARGET_NS" &>/dev/null; then
    echo "[OK] Git secret '${SECRET_NAME}' already exists"
  else
    echo "[..] Git secret '${SECRET_NAME}' not found in namespace '${TARGET_NS}'"
    read -rp "     Enter GitHub token: " GH_TOKEN
    kubectl create secret generic "$SECRET_NAME" \
      --namespace "$TARGET_NS" \
      --from-literal=username=git \
      --from-literal=password="$GH_TOKEN"
    echo "[OK] Git secret '${SECRET_NAME}' created"
  fi
fi

echo "[..] Applying GitRepository..."
kubectl apply -f "$GIT_REPO_FILE"
echo "[OK] GitRepository applied"

echo "[..] Applying Flux Kustomization..."
kubectl apply -f "$KUSTOMIZATION_FILE"
echo "[OK] Flux Kustomization applied"

echo ""
echo "=== Deployment initiated for '${APP_NAME}' (env: ${ENV_NAME}) ==="
echo "    Monitor with:"
echo "    kubectl get kustomization ${APP_NAME} -n ${TARGET_NS}"
echo "    kubectl get helmrelease -n ${TARGET_NS}"
