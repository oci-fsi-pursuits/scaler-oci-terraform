# Scaler OCI Terraform

Terraform configuration to provision all OCI infrastructure required by the
OpenGRIS Scaler OCI worker manager adapters (`oci_raw` and `oci_hpc`).

## What Gets Created

| Resource | Description |
|----------|-------------|
| VCN + Subnet | Private networking for container instances and scheduler |
| NAT / Internet Gateway | Egress for private or public subnet modes |
| Service Gateway | Direct path to OCI Object Storage and OCIR |
| Object Storage Bucket | Task payload and result storage (auto-expires after 1 day) |
| OCIR Repository | Container registry for worker images |
| Dynamic Group | Matches all container instances in the compartment |
| IAM Policies | Object Storage read/write + logging for container instances |
| Log Group + Custom Log | Container instance log aggregation |
| Scheduler Instance | *(optional)* Compute VM running `scaler_scheduler` |
| Bastion Host | *(optional)* Public jump host for SSH access to private resources |

## Prerequisites

```bash
terraform version      # >= 1.5 required
oci iam region list    # verify OCI CLI works (optional, for credential setup)
docker info            # verify Docker is running (for building worker images)
```

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- An OCI tenancy with a compartment for Scaler resources
- An SSH key pair for bastion/scheduler access
- [Docker](https://docs.docker.com/get-docker/) (for building worker images)
- The [opengris-scaler-oci](https://github.com/oci-fsi-pursuits/opengris-scaler-oci) source tree

## Quick Start

### 1. Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your OCI details
```

**Minimal configuration** (when using `~/.oci/config`):

```hcl
tenancy_ocid     = "ocid1.tenancy.oc1..aaaa..."
region           = "us-phoenix-1"
compartment_ocid = "ocid1.compartment.oc1..aaaa..."

ssh_public_key_file  = "~/.ssh/id_ed25519.pub"
ssh_private_key_path = "~/.ssh/id_ed25519"
```

**With explicit credentials** (when not using `~/.oci/config`):

```hcl
tenancy_ocid     = "ocid1.tenancy.oc1..aaaa..."
user_ocid        = "ocid1.user.oc1..aaaa..."
fingerprint      = "aa:bb:cc:..."
private_key_path = "~/.oci/oci_api_key.pem"
region           = "us-phoenix-1"
compartment_ocid = "ocid1.compartment.oc1..aaaa..."

ssh_public_key_file  = "~/.ssh/id_ed25519.pub"
ssh_private_key_path = "~/.ssh/id_ed25519"
```

See `terraform.tfvars.example` for all available options.

### 2. Initialize and Apply

```bash
make init    # or: terraform init
make plan    # or: terraform plan
make apply   # or: terraform apply
```

### 3. Build and Push the Worker Container Image

```bash
# Log in to OCIR (interactive — prompts for username and password)
make login
# Username: your OCI username (e.g. oraclecloud/user@example.com)
# Password: an OCI auth token (generate at: OCI Console > Identity > Users > Auth Tokens)

# Build and push the worker image (defaults to HPC adapter)
make build SCALER_SRC=../opengris-scaler-oci

# Or build both HPC and Raw adapter images
make build SCALER_SRC=../opengris-scaler-oci ADAPTER=both
```

The build script uses Dockerfiles from the scaler source tree to create
lightweight worker images (Python 3.12-slim + OCI SDK) and pushes them to the
OCIR repository Terraform created. At runtime, the worker manager on the
scheduler creates OCI Container Instances that pull these images.

### 4. Deploy the Scheduler (Optional)

Enable the scheduler and bastion in `terraform.tfvars`:

```hcl
create_scheduler_instance = true
create_bastion            = true
```

Then apply and deploy:

```bash
make apply
# Wait ~2 minutes for cloud-init, then:
make deploy SCALER_SRC=../opengris-scaler-oci

# Or directly:
$(terraform output -raw deploy_scheduler_command | sed 's|<path-to-scaler>|../opengris-scaler-oci|')
```

### 5. Verify the Scheduler

```bash
# SSH to the scheduler (reads connection info from Terraform outputs)
make ssh

# On the scheduler instance:
sudo journalctl -u scaler-scheduler -f    # view logs
sudo systemctl status scaler-scheduler    # check status
sudo ss -tlnp | grep 2345                # verify port is listening
```

## SSH Key Configuration

SSH keys can be configured in three ways:

| Method | Variables to Set |
|--------|-----------------|
| **Key file** (recommended) | `ssh_public_key_file = "~/.ssh/id_ed25519.pub"` |
| **Inline string** | `scheduler_ssh_public_key = "ssh-ed25519 AAAA..."` |
| **Separate bastion key** | `bastion_ssh_public_key = "ssh-ed25519 BBBB..."` |

Always set `ssh_private_key_path` so output commands and helper scripts use
the correct key:

```hcl
ssh_private_key_path = "~/.ssh/id_ed25519"
```

## OCI Authentication

The Terraform provider supports three authentication methods:

| Method | When to Use |
|--------|-------------|
| **~/.oci/config** (default) | Leave `user_ocid`, `fingerprint`, `private_key_path` empty |
| **Explicit credentials** | Set all three in `terraform.tfvars` |
| **1Password CLI** | Extract with `op item get "OCI API Key" --vault API --fields user_ocid` |

## Running the Test Harness

The test harness validates the OCI infrastructure in four phases.

### Phase 1 — OCI Connectivity

```bash
python tests/worker_manager_adapter/oci_hpc/oci_hpc_test_harness.py \
  --compartment-id "$(terraform output -raw compartment_id)" \
  --phase connectivity
```

### Phase 2 — Object Storage

```bash
python tests/worker_manager_adapter/oci_hpc/oci_hpc_test_harness.py \
  --compartment-id "$(terraform output -raw compartment_id)" \
  --phase storage
```

### Phase 3 — Container Instance Lifecycle

```bash
python tests/worker_manager_adapter/oci_hpc/oci_hpc_test_harness.py \
  --compartment-id "$(terraform output -raw compartment_id)" \
  --subnet-id "$(terraform output -raw subnet_id)" \
  --availability-domain "$(terraform output -raw availability_domain)" \
  --container-image docker.io/library/alpine:latest \
  --phase lifecycle
```

### Phase 4 — Scheduler Task Tests

From the scheduler instance (recommended):

```bash
make ssh

# On the scheduler:
source /opt/scaler/venv/bin/activate
cd /opt/scaler/src
python tests/worker_manager_adapter/oci_hpc/oci_hpc_test_harness.py \
  --compartment-id "<compartment_ocid>" \
  --scheduler tcp://127.0.0.1:2345 \
  --phase scheduler
```

### Running All Phases

```bash
terraform output -json scaler_config > /tmp/scaler_config.json

python tests/worker_manager_adapter/oci_hpc/oci_hpc_test_harness.py \
  --config /tmp/scaler_config.json \
  --scheduler tcp://127.0.0.1:2345
```

## Architecture

```
                     ┌─────────────────────────────────┐
                     │           Your Machine           │
                     │  (test harness / scaler client)  │
                     └──────────┬──────────────────────┘
                                │ SSH tunnel / direct
                     ┌──────────▼──────────────────────┐
                     │     Bastion Host (public IP)     │
                     │        10.0.2.0/24 subnet        │
                     └──────────┬──────────────────────┘
                                │
              ┌─────────────────▼─────────────────────────────┐
              │              Private Subnet (10.0.1.0/24)      │
              │                                                │
              │  ┌──────────────────┐  ┌────────────────────┐  │
              │  │    Scheduler     │  │  Container Instance │  │
              │  │  (compute VM)   │◄─│  (per-task worker)  │  │
              │  │  :2345          │  │  oci_hpc adapter    │  │
              │  └──────────────────┘  └────────┬───────────┘  │
              │                                 │              │
              └─────────────────────────────────┼──────────────┘
                                                │
                                    ┌───────────▼───────────┐
                                    │    Object Storage     │
                                    │  (task payloads and   │
                                    │   results)            │
                                    └───────────────────────┘
```

## Make Targets

```bash
make help       # Show all targets
make init       # terraform init
make plan       # terraform plan
make apply      # terraform apply
make destroy    # terraform destroy
make login      # Log in to OCIR (prompts for username and auth token)
make build      # Build and push worker images (SCALER_SRC=<path> ADAPTER=hpc|raw|both)
make deploy     # Deploy scaler source to scheduler (SCALER_SRC=<path>)
make ssh        # SSH to scheduler via bastion
make validate   # Validate Terraform config
make fmt        # Format Terraform files
```

## Useful Terraform Outputs

```bash
terraform output bastion_public_ip           # Bastion SSH target
terraform output bastion_ssh_command          # Ready-to-run SSH command
terraform output bastion_ssh_to_scheduler     # SSH to scheduler via bastion
terraform output bastion_tunnel_to_scheduler  # Port-forward scheduler
terraform output deploy_scheduler_command     # Deploy local source
terraform output build_and_push_command       # Build worker image
terraform output ocir_docker_login_command    # OCIR login template
terraform output scheduler_address            # tcp://<private_ip>:2345
terraform output -json scaler_config          # Full config JSON
```

## Cleanup

```bash
make destroy   # or: terraform destroy
```

This removes all OCI resources. The bastion and scheduler instances will be
terminated, networking torn down, and the Object Storage bucket deleted.

## File Structure

```
scaler-oci-terraform/
├── main.tf                 # Providers, data sources, locals
├── variables.tf            # All input variables with validation
├── outputs.tf              # All outputs (IPs, config JSON, helper commands)
├── networking.tf           # VCN, gateways, route tables, security lists, subnet
├── storage.tf              # Object Storage bucket with lifecycle
├── registry.tf             # OCIR repository with region key mapping
├── iam.tf                  # Dynamic Group + IAM Policies (home region)
├── logging.tf              # Log Group + Custom Log
├── compute.tf              # Scheduler compute instance (optional)
├── bastion.tf              # Bastion host (optional)
├── Makefile                # Make targets for common operations
├── terraform.tfvars        # Your variable values (gitignored)
├── terraform.tfvars.example # Annotated example with all options
└── scripts/
    ├── build-and-push.sh           # Build + push worker images to OCIR
    ├── deploy-scheduler.sh         # Deploy local scaler source to scheduler
    ├── ssh-to-scheduler.sh         # SSH convenience wrapper (reads TF outputs)
    └── cloud-init-scheduler.yaml   # Cloud-init template for scheduler VM
```
