# Acme Corp Minecraft Server — Infrastructure as Code

> **Course Project Part 2** — Automated successor to the manual Part 1 setup.

In Part 1, the Minecraft server was configured by hand: launching an EC2 instance through the AWS Console, SSH-ing in, installing Java, downloading the server jar, and writing a systemd unit file step by step. It worked — but it was entirely manual, not reproducible, and fragile.

Part 2 automates the entire lifecycle using Infrastructure as Code. The same outcome (a running, auto-restarting Minecraft server on EC2) is achieved without ever opening the AWS Console or typing a single command on the remote machine by hand.

---

## Table of Contents

- [Background](#background)
- [Architecture](#architecture)
- [Requirements](#requirements)
- [Repository Structure](#repository-structure)
- [Pipeline Diagram](#pipeline-diagram)
- [Setup & Configuration](#setup--configuration)
- [Running the Pipeline](#running-the-pipeline)
- [Connecting to the Minecraft Server](#connecting-to-the-minecraft-server)
- [Teardown](#teardown)
- [Design Decisions](#design-decisions)
- [Resources & Sources](#resources--sources)

---

## Background

### What We Are Doing

This project fully automates the lifecycle of a Minecraft Java Edition server on AWS — from bare metal to a live, connectable game server — without ever touching the AWS Management Console. The pipeline:

1. **Provisions** an EC2 instance with the required networking (VPC, subnet, internet gateway, security group) using **Terraform**.
2. **Configures** the instance and deploys the Minecraft server inside a Docker container using **Ansible**.
3. **Registers** a **systemd service** so the server starts on every boot and stops cleanly (sending the `stop` RCON command) to prevent world data corruption.

### How We Do It

| Stage | Tool | What it does |
|---|---|---|
| Infrastructure Provisioning | Terraform ≥ 1.6 | Creates VPC, subnets, security groups, key pair, EC2 instance |
| Inventory Generation | Bash | Reads Terraform output and writes the Ansible hosts file |
| Server Configuration | Ansible ≥ 2.15 | Installs Docker, deploys container, registers systemd service |
| Container Runtime | Docker / `itzg/minecraft-server` | Runs the Minecraft Java server process |
| Auto-restart | systemd | Starts on boot, restarts on failure, stops gracefully on shutdown |

---

## Architecture

```
Your Workstation
      │
      ├── terraform apply   ──►  AWS VPC / Subnet / Security Group / EC2
      │
      ├── generate_inventory.sh  ──►  ansible/inventory/hosts.ini
      │
      └── ansible-playbook  ──►  EC2 Instance
                                      │
                                      ├── Docker Engine
                                      │       └── itzg/minecraft-server container
                                      │               └── port 25565 (TCP/UDP)
                                      │
                                      └── systemd: minecraft.service
                                              ├── Restart=on-failure
                                              └── ExecStop → rcon-cli stop
```

### AWS Resources Created

- **VPC** (`10.0.0.0/16`) with DNS hostnames enabled
- **Public Subnet** (`10.0.1.0/24`) in `us-east-1a`
- **Internet Gateway** + **Route Table** for public internet access
- **Security Group** (`minecraft_security_settings`) — inbound TCP/UDP 25565 (Minecraft), inbound TCP 22 (SSH)
- **EC2 Key Pair** from your local public key
- **EC2 Instance** — Ubuntu **24.04 LTS**, `t3.micro`, **10 GiB** gp3 EBS volume

---

## Requirements

### Tooling (with versions)

| Tool | Minimum Version | Install |
|---|---|---|
| [Terraform](https://developer.hashicorp.com/terraform/install) | 1.6.0 | `brew install terraform` or official installer |
| [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) | 2.15.0 | `pip install ansible` |
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | 2.x | Official installer |
| [nmap](https://nmap.org/download) | 7.x | `brew install nmap` or `apt install nmap` |
| [Git](https://git-scm.com/) | 2.x | Usually pre-installed |

> **Windows users:** Run all commands from WSL2 (Ubuntu) or a Linux VM. The scripts assume a POSIX shell environment.

### AWS Credentials

This project targets **AWS Academy Learner Lab** credentials. Retrieve them as follows:

1. Open the **Learner Lab** module on Canvas.
2. Click **AWS Details** → **Show** next to *AWS CLI*.
3. Copy the three export lines and paste them in your terminal:

```bash
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
```

> Learner Lab credentials expire after a few hours. Re-export them if you see `ExpiredTokenException`.

### SSH Key Pair

Ansible connects to the EC2 instance over SSH. You need an RSA key pair at `~/.ssh/id_rsa` / `~/.ssh/id_rsa.pub`. Generate one if you do not have it:

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
```

---

## Repository Structure

```
minecraft-server/
├── terraform/                  # Infrastructure provisioning
│   ├── main.tf                 # VPC, subnets, SG, EC2
│   ├── variables.tf            # All input variables
│   ├── outputs.tf              # Instance IP, nmap command
│   └── terraform.tfvars.example
│
├── ansible/                    # Server configuration
│   ├── ansible.cfg             # Ansible settings
│   ├── minecraft.yml           # Top-level playbook
│   ├── requirements.yml        # community.docker collection
│   └── roles/
│       └── minecraft/
│           ├── tasks/main.yml  # Install Docker, deploy container
│           ├── handlers/main.yml
│           └── templates/
│               └── minecraft.service.j2   # systemd unit file
│
├── scripts/
│   ├── deploy.sh               # One-command full deployment
│   ├── generate_inventory.sh   # Terraform → Ansible inventory
│   └── teardown.sh             # Destroy all AWS resources
│
├── .gitignore
└── README.md
```

---

## Pipeline Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Local Workstation                            │
│                                                                      │
│  1. Export AWS credentials (from Learner Lab)                        │
│  2. Copy terraform.tfvars.example → terraform.tfvars                │
│  3. Run: ./scripts/deploy.sh                                         │
│                │                                                     │
│                ▼                                                     │
│  ┌─────────────────────────┐                                         │
│  │   terraform init        │  Downloads AWS provider plugin          │
│  │   terraform plan        │  Shows what will be created             │
│  │   terraform apply       │  Creates VPC, SG, EC2, key pair         │
│  └────────────┬────────────┘                                         │
│               │ outputs: instance_public_ip                          │
│               ▼                                                      │
│  ┌─────────────────────────┐                                         │
│  │  generate_inventory.sh  │  Writes ansible/inventory/hosts.ini     │
│  └────────────┬────────────┘                                         │
│               │                                                      │
│               ▼                                                      │
│  ┌─────────────────────────┐                                         │
│  │  ansible-playbook       │  SSH into EC2 instance                  │
│  │  minecraft.yml          │  ├── Install Docker Engine              │
│  │                         │  ├── Pull itzg/minecraft-server image   │
│  │                         │  ├── Deploy minecraft.service (systemd) │
│  │                         │  └── Start & enable service             │
│  └────────────┬────────────┘                                         │
│               │                                                      │
│               ▼                                                      │
│  ┌─────────────────────────┐                                         │
│  │  nmap -sV -Pn           │  Confirms port 25565 is open            │
│  │  -p T:25565 <IP>        │                                         │
│  └─────────────────────────┘                                         │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Setup & Configuration

### 1. Clone the Repository

```bash
git clone https://github.com/<your-username>/minecraft-server.git
cd minecraft-server
```

### 2. Install Ansible Galaxy Requirements

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
cd ..
```

### 3. Configure Terraform Variables

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars` to match your setup. The key fields:

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `us-east-1` | AWS region to deploy into |
| `instance_type` | `t3.micro` | EC2 instance size (matches Part 1) |
| `root_volume_size` | `10` | EBS volume in GiB (matches Part 1) |
| `public_key_path` | `~/.ssh/id_rsa.pub` | Path to your SSH public key |
| `ssh_allowed_cidr` | `0.0.0.0/0` | Restrict SSH to your IP for security |

### 4. Export AWS Credentials

```bash
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
```

---

## Running the Pipeline

### Option A — One Command (Recommended)

```bash
./scripts/deploy.sh
```

This script runs all stages in order:
1. Runs `terraform init`, `plan`, and `apply`
2. Generates the Ansible inventory from Terraform output
3. Waits for SSH to become available on the new instance
4. Installs Ansible Galaxy collections
5. Runs the Ansible playbook
6. Verifies the server with `nmap`

### Option B — Step by Step

If you prefer to run each stage manually:

```bash
# Stage 1 — Provision infrastructure
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
cd ..

# Stage 2 — Generate Ansible inventory
./scripts/generate_inventory.sh

# Stage 3 — Configure instance and deploy Minecraft
cd ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook minecraft.yml
cd ..

# Stage 4 — Verify
INSTANCE_IP=$(cd terraform && terraform output -raw instance_public_ip)
nmap -sV -Pn -p T:25565 "$INSTANCE_IP"
```

### Expected nmap Output

A successful deployment will produce output similar to:

```
Starting Nmap 7.95
Nmap scan report for ec2-X-X-X-X.compute-1.amazonaws.com (X.X.X.X)
Host is up.

PORT      STATE SERVICE   VERSION
25565/tcp open  minecraft Minecraft 1.21 (Protocol: 767, Message: Acme Corp Minecraft Server, Users: 0/20)

Nmap done: 1 IP address (1 host up) scanned in 5.42 seconds
```

---

## Connecting to the Minecraft Server

1. Launch **Minecraft Java Edition** (version matching the server, default: latest).
2. Click **Multiplayer** → **Add Server**.
3. Enter the **Server Address**: the public IP output by Terraform (or from `terraform output instance_public_ip`).
4. Click **Done** → **Join Server**.

To retrieve the IP at any time:

```bash
cd terraform && terraform output instance_public_ip
```

---

## Teardown

To destroy all AWS resources and avoid incurring costs:

```bash
./scripts/teardown.sh
```

You will be prompted to type `yes` to confirm. This runs `terraform destroy` and removes all infrastructure created by this project.

> **Note:** Minecraft world data stored in `/opt/minecraft/data` on the EC2 instance will be permanently lost. Back up the volume snapshot if you want to keep your world.

---

## Design Decisions

**Why Docker instead of a bare-metal Java install?**
Part 1 installed `openjdk-21-jre-headless` directly on the host, downloaded a specific `server.jar`, and ran it as a dedicated `minecraft` OS user. This works but has real drawbacks: upgrading the server means SSHing in to swap jars manually, and the Java version is pinned to whatever `apt` provides. The [`itzg/minecraft-server`](https://github.com/itzg/docker-minecraft-server) Docker image handles the Java runtime, version pinning, EULA acceptance, and all server configuration through environment variables. Upgrading is a single `docker pull`. The host OS stays clean.

**Why systemd wrapping Docker instead of running Docker Compose directly?**
Part 1's systemd unit ran the Java process directly. Here, systemd manages the `docker run` command instead — same reliable service lifecycle (`Restart=on-failure`, `WantedBy=multi-user.target` for auto-start on reboot), but Docker handles the process isolation. Critically, `ExecStop` sends `rcon-cli stop` to the container before killing it, which triggers a clean world save. Part 1 lacked this — the server was not shutting down properly, which risked world corruption on reboot.

**Why Terraform for networking + Ansible for configuration?**
Terraform excels at declarative infrastructure that can be created and destroyed atomically (VPC, subnets, security groups, EC2). Ansible excels at idempotent configuration management over SSH (installing packages, deploying files, enabling services). Using both tools for what they are each best at avoids the pitfalls of doing everything in a single bash `user_data` script, which is harder to debug, cannot be re-run cleanly, and is explicitly disallowed by the project requirements.

**Why not `user_data`?**
The project brief explicitly flags `user_data` as bad practice. `user_data` runs once on first boot, produces no structured output, and cannot be re-applied without reprovisioning the instance. Ansible gives us idempotent, re-runnable, readable configuration with proper error reporting.

---

## Resources & Sources

- [itzg/docker-minecraft-server](https://github.com/itzg/docker-minecraft-server) — Docker image used for the server
- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Ansible community.docker Collection](https://docs.ansible.com/ansible/latest/collections/community/docker/)
- [Ansible systemd module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/systemd_module.html)
- [Docker Engine install on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [GitHub Markdown syntax guide](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax)
