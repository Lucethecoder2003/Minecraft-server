#!/usr/bin/env bash
# scripts/teardown.sh
# Destroys all AWS resources created by Terraform.
# WARNING: This is irreversible. Minecraft world data will be lost.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(dirname "$SCRIPT_DIR")/terraform"

RED='\033[0;31m'
NC='\033[0m'

echo -e "${RED}WARNING: This will DESTROY all provisioned AWS resources.${NC}"
read -r -p "Are you sure? Type 'yes' to confirm: " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
  echo "Aborted."
  exit 0
fi

cd "$TF_DIR"
terraform destroy -auto-approve
echo "All resources destroyed."
