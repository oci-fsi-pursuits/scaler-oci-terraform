# Scaler OCI Terraform

This Terraform configuration provisions the complete OCI infrastructure for the OpenGRIS Scaler OCI worker manager adapters (`oci_raw` and `oci_hpc`). It automates deployment of networking, storage, container registries, IAM, and optional scheduler/bastion resources.

> **Deploying the Scaler adapter?** After running `make apply`, jump to [Exporting Config for the Scaler Adapter](#exporting-config-for-the-scaler-adapter) to get a ready-to-use config file.
>
> This repo is also fully usable standalone — it provisions general-purpose OCI networking, Object Storage, OCIR, and IAM that any OCI Container Instance workload can use.

---

## Prerequisites

- Terraform ≥ 1.5
- An OCI tenancy with a dedicated compartment
- An SSH key pair for scheduler/bastion access
- Docker (for building container images)
- The `opengris-scaler-oci` source repository (only needed for `make build` and `make deploy`)

---

## Infrastructure Created

| Component | Purpose |
|-----------|---------|
| VCN & Subnet | Private networking for Container Instances |
| NAT / Internet / Service Gateways | Egress to OCI services (Object Storage, OCIR) without public IPs |
| Object Storage Bucket | Task payloads and results (7-day auto-expiry by default) |
| OCIR Repository | Container registry for worker images |
| Dynamic Group + IAM Policies | Least-privilege access for Container Instances |
| Log Group | Centralized instance logging |
| Scheduler VM *(optional)* | Compute instance running `scaler-scheduler` and `scaler-worker-manager` as systemd services |
| Bastion Host *(optional)* | Public jump server for SSH access to the scheduler |

---

## Quick Start

### Step 1 — Configure

Copy and edit the example variables file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

**Minimum required values:**

```hcl
tenancy_ocid     = "ocid1.tenancy.oc1...<your-tenancy>"
region           = "us-ashburn-1"
compartment_ocid = "ocid1.compartment.oc1...<your-compartment>"

# SSH key for scheduler/bastion access
ssh_public_key_file  = "~/.ssh/id_ed25519.pub"
ssh_private_key_path = "~/.ssh/id_ed25519"
```

**Authentication — choose one:**

```hcl
# Option A: use ~/.oci/config (simplest for local dev — leave these commented out)
# user_ocid        = ""
# fingerprint      = ""
# private_key_path = ""

# Option B: explicit credentials
# user_ocid        = "ocid1.user.oc1...<your-user>"
# fingerprint      = "aa:bb:cc:..."
# private_key_path = "~/.oci/oci_api_key.pem"
```

**Optional: restrict SSH access to your IP** (recommended before making repos public):

```hcl
# ssh_source_cidr = "203.0.113.42/32"  # your public IP
# Default is VCN-internal only (10.0.0.0/16)
```

### Step 2 — Provision Infrastructure

```bash
make init     # Initialize Terraform providers
make plan     # Preview what will be created
make apply    # Deploy all resources (~2-3 minutes)
```

### Step 3 — Build Worker Images

Authenticate with OCIR, then build and push the container images:

```bash
make login                              # Docker login to OCIR (prompts for auth token)
make build SCALER_SRC=../opengris-scaler-oci ADAPTER=hpc   # OCI HPC image
make build SCALER_SRC=../opengris-scaler-oci ADAPTER=raw   # OCI Raw image
# Or build both at once:
make build SCALER_SRC=../opengris-scaler-oci ADAPTER=both
```

### Step 4 — Deploy Scheduler (Optional)

To run the scheduler on an OCI VM with systemd services pre-configured, enable these in `terraform.tfvars`:

```hcl
create_scheduler_instance = true
create_bastion            = true   # recommended for SSH access
```

Then:

```bash
make apply
make deploy SCALER_SRC=../opengris-scaler-oci
```

> **First-boot note:** The scheduler VM compiles C++ dependencies (Cap'n Proto, ZeroMQ, libuv) from source on first boot. This takes **15–25 minutes**. Monitor progress with:
> ```bash
> make ssh
> sudo tail -f /var/log/scaler-init.log
> ```
> Wait until you see `scaler install complete — starting services` before running `systemctl status`.

### Step 5 — Verify

```bash
make ssh
sudo systemctl status scaler-scheduler
sudo systemctl status scaler-worker-manager
sudo ss -tlnp | grep 2345   # scheduler should be listening
```

---

## Exporting Config for the Scaler Adapter

Once `make apply` completes, export the configuration in the format the Scaler adapter expects:

```bash
terraform output -json scaler_config > .scaler_oci_config.json
```

This single file contains all the parameters (`compartment_id`, `subnet_id`, `availability_domain`, `object_storage_namespace`, `object_storage_bucket`, `container_image`, etc.) needed by the OpenGRIS Scaler OCI adapter. Copy it to the `opengris-scaler-oci` directory and follow from **Step 2** of the [OCI integration guide](https://github.com/oci-fsi-pursuits/opengris-scaler-oci/blob/main/ReadMeOCI.Md):

```bash
cp .scaler_oci_config.json ../opengris-scaler-oci/
cd ../opengris-scaler-oci
# Continue with Step 2 — build-and-push
```

---

## Testing Infrastructure

The test harness in `opengris-scaler-oci` validates all four phases using Terraform outputs directly:

```bash
# Phase 1+2 — Connectivity and Object Storage
python tests/worker_manager_adapter/oci_hpc/oci_hpc_test_harness.py \
  --compartment-id "$(terraform output -raw compartment_id)" \
  --phase connectivity

# Phase 3 — Container Instance lifecycle
python tests/worker_manager_adapter/oci_hpc/oci_hpc_test_harness.py \
  --compartment-id "$(terraform output -raw compartment_id)" \
  --subnet-id "$(terraform output -raw subnet_id)" \
  --availability-domain "$(terraform output -raw availability_domain)" \
  --container-image "$(terraform output -raw ocir_image_uri)-hpc" \
  --phase lifecycle

# Phase 4 — Scheduler integration (run from scheduler VM)
# ssh in first: make ssh
# then: python tests/.../oci_hpc_test_harness.py --phase tasks --scheduler-address tcp://127.0.0.1:2345
```

---

## SSH Access

```bash
make ssh                                   # SSH to scheduler via bastion
terraform output bastion_ssh_command       # Get the raw SSH command string
```

---

## Useful Commands

```bash
make help                              # All available targets
make validate                          # Check Terraform syntax
make fmt                               # Auto-format .tf files
terraform output scaler_config         # View full config JSON
terraform output -json scaler_config   # Machine-readable JSON (pipe to file)
```

---

## Object Storage Lifecycle

The task bucket defaults to **7-day object expiry**. This is intentionally longer than the default `job_timeout_seconds` (1 hour) to ensure results are always available when the adapter polls for them. You can reduce this after confirming your tasks complete well within the window:

```hcl
bucket_lifecycle_days = 2   # safe minimum if tasks always finish within 1 day
```

Setting this below 2 days is blocked by a Terraform validation rule.

---

## Security Notes

- **SSH access** defaults to VCN-internal only (`10.0.0.0/16`). Set `ssh_source_cidr` to your public IP for remote access.
- **Dynamic Group policy** grants Container Instances read access to input objects and write access to result objects in the task bucket. It does not grant access to other compartment resources.
- **IAM policy** for the scheduler VM grants `manage compute-container-family` scoped to the provisioned compartment.
- OCIR repositories default to private (`ocir_repository_is_public = false`).

---

## Cleanup

Remove all provisioned resources:

```bash
make destroy
```

This terminates compute instances, removes networking, and deletes the Object Storage bucket and all its contents.

---

## File Organisation

| File | Purpose |
|------|---------|
| `main.tf` | Provider configuration |
| `variables.tf` | Input variable definitions and validation |
| `outputs.tf` | Output values including `scaler_config` JSON |
| `networking.tf` | VCN, subnets, gateways, security lists |
| `storage.tf` | Object Storage bucket and lifecycle policy |
| `registry.tf` | OCIR repository |
| `iam.tf` | Dynamic Group and IAM policies |
| `compute.tf` | Optional scheduler instance with cloud-init |
| `bastion.tf` | Optional public jump host |
| `scripts/` | Build, deploy, SSH, and cloud-init helper scripts |
| `terraform.tfvars.example` | Annotated example configuration |
