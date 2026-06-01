#!/usr/bin/env bash
# scripts/deploy.sh
# Full end-to-end deployment:
#   1. Provision AWS infrastructure with Terraform
#   2. Generate Ansible inventory
#   3. Configure the EC2 instance and start Minecraft with Ansible
#   4. Verify the server is reachable with nmap

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TF_DIR="$REPO_ROOT/terraform"
ANSIBLE_DIR="$REPO_ROOT/ansible"

# ── Colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

step() { echo -e "\n${YELLOW}==> $1${NC}"; }
ok()   { echo -e "${GREEN}✔  $1${NC}"; }

# ── Preflight checks ─────────────────────────────────────────────────────────
step "Checking required tools..."
for tool in terraform ansible ansible-galaxy nmap aws; do
  if ! command -v "$tool" &>/dev/null; then
    echo "ERROR: '$tool' is not installed or not in PATH."
    exit 1
  fi
done
ok "All required tools found."

# ── Verify AWS credentials ────────────────────────────────────────────────────
step "Verifying AWS credentials..."
aws sts get-caller-identity --output text --query 'Account' > /dev/null
ok "AWS credentials are valid."

# ── Terraform ────────────────────────────────────────────────────────────────
step "Initialising Terraform..."
cd "$TF_DIR"
terraform init -upgrade

step "Planning infrastructure changes..."
terraform plan -out=tfplan

step "Applying Terraform plan..."
terraform apply tfplan
rm -f tfplan
ok "Infrastructure provisioned."

# ── Inventory ────────────────────────────────────────────────────────────────
step "Generating Ansible inventory..."
bash "$SCRIPT_DIR/generate_inventory.sh"

# ── Wait for SSH to become available ─────────────────────────────────────────
step "Waiting for SSH to become available on the new instance (up to 2 min)..."
INSTANCE_IP=$(terraform output -raw instance_public_ip)
for i in $(seq 1 24); do
  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
        -i ~/.ssh/minecraft_part2 ubuntu@"$INSTANCE_IP" "exit" 2>/dev/null; then
    ok "SSH is up."
    break
  fi
  echo "  Attempt $i/24 — sleeping 5s..."
  sleep 5
done

# ── Ansible ──────────────────────────────────────────────────────────────────
step "Installing Ansible Galaxy requirements..."
cd "$ANSIBLE_DIR"
ansible-galaxy collection install -r requirements.yml

step "Running Ansible playbook..."
ansible-playbook minecraft.yml
ok "Minecraft server configured and running."

# ── Verify ───────────────────────────────────────────────────────────────────
step "Verifying Minecraft server with nmap..."
echo ""
nmap -sV -Pn -p T:25565 "$INSTANCE_IP"
echo ""
ok "Deployment complete! Connect to: $INSTANCE_IP:25565"
