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

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- An OCI tenancy with:
  - A compartment for Scaler resources
  - An API signing key (`~/.oci/config`)
- [Docker](https://docs.docker.com/get-docker/) (for building worker images)
- The [opengris-scaler-oci](../opengris-scaler-oci) source tree

## Quick Start

### 1. Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your OCI credentials and preferences
```

Key variables to set:

| Variable | Description |
|----------|-------------|
| `tenancy_ocid` | Your OCI tenancy OCID |
| `user_ocid` | Your OCI user OCID |
| `fingerprint` | API key fingerprint |
| `private_key_path` | Path to your OCI API private key |
| `region` | Target OCI region (e.g. `us-phoenix-1`) |
| `compartment_ocid` | Compartment OCID for all resources |

### 2. Initialize and Apply

```bash
terraform init
terraform plan
terraform apply
```

### 3. Build and Push the Worker Container Image

The scaler project includes Dockerfiles for both adapters. Use the build script
to compile and push to OCIR:

```bash
# Log in to OCIR (replace <username> and <auth_token>)
docker login $(terraform output -raw ocir_login_server) \
  -u $(terraform output -raw object_storage_namespace)/<username> \
  -p <auth_token>

# Build and push the HPC worker image
./scripts/build-and-push.sh \
  --scaler-src ../opengris-scaler-oci \
  --ocir-uri "$(terraform output -raw ocir_image_uri)" \
  --adapter hpc

# Or build both HPC and Raw images
./scripts/build-and-push.sh \
  --scaler-src ../opengris-scaler-oci \
  --ocir-uri "$(terraform output -raw ocir_image_uri)" \
  --adapter both
```

### 4. Deploy the Scheduler (Optional)

To run an end-to-end test you need a scheduler instance. Enable it in
`terraform.tfvars`:

```hcl
create_scheduler_instance = true
scheduler_ssh_public_key  = "ssh-ed25519 AAAA..."  # your public key

create_bastion = true  # needed for SSH access to the private scheduler
```

Then apply and deploy your local scaler source:

```bash
terraform apply

# Wait ~2 minutes for cloud-init to install Python 3.11 and build deps,
# then deploy the local scaler source:
./scripts/deploy-scheduler.sh \
  --scaler-src ../opengris-scaler-oci \
  --bastion-ip "$(terraform output -raw bastion_public_ip)" \
  --scheduler-ip "$(terraform output -raw scheduler_private_ip)"
```

The deploy script will:
1. Create a tarball of your local scaler source
2. SCP it to the scheduler through the bastion
3. Create a Python 3.11 virtualenv and `pip install -e .`
4. Restart the `scaler-scheduler` systemd service

### 5. Verify the Scheduler

```bash
# SSH to the scheduler through the bastion
ssh -i ~/.ssh/scaler_scheduler \
  -o 'ProxyCommand=ssh -i ~/.ssh/scaler_scheduler -W %h:%p opc@<bastion_ip>' \
  opc@<scheduler_ip>

# On the scheduler instance:
sudo journalctl -u scaler-scheduler -f    # view logs
sudo systemctl status scaler-scheduler    # check status
sudo ss -tlnp | grep 2345                # verify port is listening
```

Or use Terraform outputs directly:

```bash
$(terraform output -raw bastion_ssh_to_scheduler)
```

## Running the Test Harness

The test harness validates the OCI infrastructure in four phases.

### Phase 1 — OCI Connectivity

Tests API authentication, compartment access, subnet reachability, and
availability domain resolution.

```bash
python tests/worker_manager_adapter/oci_hpc/oci_hpc_test_harness.py \
  --compartment-id "$(terraform output -raw compartment_id)" \
  --phase connectivity
```

### Phase 2 — Object Storage

Creates a temporary bucket, writes/reads/deletes a test object, and cleans up.

```bash
python tests/worker_manager_adapter/oci_hpc/oci_hpc_test_harness.py \
  --compartment-id "$(terraform output -raw compartment_id)" \
  --phase storage
```

### Phase 3 — Container Instance Lifecycle

Launches a minimal container instance (alpine), waits for it to reach INACTIVE,
and deletes it. Validates that container instances can be created and run to
completion in the provisioned infrastructure.

```bash
python tests/worker_manager_adapter/oci_hpc/oci_hpc_test_harness.py \
  --compartment-id "$(terraform output -raw compartment_id)" \
  --subnet-id "$(terraform output -raw subnet_id)" \
  --availability-domain "$(terraform output -raw availability_domain)" \
  --container-image docker.io/library/alpine:latest \
  --phase lifecycle
```

### Phase 4 — Scheduler Task Tests

Connects to a running scheduler and submits real Scaler tasks (`math.sqrt`,
parallel `map`, compute-intensive work). Requires the scheduler instance to be
deployed with your local scaler source.

**From the scheduler instance** (recommended — avoids macOS C++ build issues):

```bash
# SSH to scheduler
$(terraform output -raw bastion_ssh_to_scheduler)

# On the scheduler:
source /opt/scaler/venv/bin/activate
cd /opt/scaler/src

python tests/worker_manager_adapter/oci_hpc/oci_hpc_test_harness.py \
  --compartment-id "<compartment_ocid>" \
  --scheduler tcp://127.0.0.1:2345 \
  --phase scheduler
```

**From your local machine** (requires scaler C++ extensions built):

```bash
# Open SSH tunnel through bastion
$(terraform output -raw bastion_tunnel_to_scheduler)

# In another terminal:
python tests/worker_manager_adapter/oci_hpc/oci_hpc_test_harness.py \
  --compartment-id "$(terraform output -raw compartment_id)" \
  --scheduler tcp://127.0.0.1:2345 \
  --phase scheduler
```

### Running All Phases

```bash
python tests/worker_manager_adapter/oci_hpc/oci_hpc_test_harness.py \
  --compartment-id "$(terraform output -raw compartment_id)" \
  --subnet-id "$(terraform output -raw subnet_id)" \
  --availability-domain "$(terraform output -raw availability_domain)" \
  --container-image docker.io/library/alpine:latest \
  --scheduler tcp://127.0.0.1:2345
```

Or use the JSON config output:

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
terraform destroy
```

This removes all OCI resources. The bastion and scheduler instances will be
terminated, networking torn down, and the Object Storage bucket deleted.

## File Structure

```
scaler-oci-terraform/
├── main.tf                 # Providers, data sources, locals
├── variables.tf            # All input variables
├── outputs.tf              # All outputs (IPs, config JSON, helper commands)
├── networking.tf           # VCN, gateways, route tables, security lists, subnet
├── storage.tf              # Object Storage bucket with lifecycle
├── registry.tf             # OCIR repository with region key mapping
├── iam.tf                  # Dynamic Group + IAM Policies (home region)
├── logging.tf              # Log Group + Custom Log
├── compute.tf              # Scheduler compute instance (optional)
├── bastion.tf              # Bastion host (optional)
├── terraform.tfvars        # Your variable values (gitignored)
├── terraform.tfvars.example # Annotated example
└── scripts/
    ├── build-and-push.sh           # Build + push worker images to OCIR
    ├── deploy-scheduler.sh         # Deploy local scaler source to scheduler
    └── cloud-init-scheduler.yaml   # Cloud-init template for scheduler VM
```
