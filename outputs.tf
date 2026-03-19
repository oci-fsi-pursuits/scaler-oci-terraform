##############################################################################
# Outputs
#
# These values map directly to the Scaler OCI adapter configuration fields:
#   - OCIRawWorkerAdapterConfig (oci_raw adapter)
#   - OCIContainerInstanceWorker / OCIHPCTaskManager (oci_hpc adapter)
#   - OCIProvisioner config JSON
##############################################################################

# ---------------------------------------------------------------------------
# Core identifiers (used by both oci_raw and oci_hpc adapters)
# ---------------------------------------------------------------------------

output "compartment_id" {
  description = "OCI Compartment OCID — maps to config.compartment_id"
  value       = var.compartment_ocid
}

output "region" {
  description = "OCI region (target) — maps to config.oci_region"
  value       = var.region
}

output "home_region" {
  description = "OCI home region — where IAM resources (Dynamic Group, Policies) are created"
  value       = local.home_region
}

output "availability_domain" {
  description = "Availability Domain name — maps to config.availability_domain"
  value       = local.availability_domain
}

output "subnet_id" {
  description = "Subnet OCID for container instance VNICs — maps to config.subnet_id"
  value       = oci_core_subnet.this.id
}

# ---------------------------------------------------------------------------
# Object Storage (used by oci_hpc adapter)
# ---------------------------------------------------------------------------

output "object_storage_namespace" {
  description = "OCI Object Storage tenancy namespace — maps to object_storage_namespace"
  value       = local.namespace
}

output "object_storage_bucket" {
  description = "Object Storage bucket name — maps to object_storage_bucket"
  value       = oci_objectstorage_bucket.this.name
}

output "object_storage_prefix" {
  description = "Key prefix for task data — maps to object_storage_prefix"
  value       = var.object_storage_prefix
}

# ---------------------------------------------------------------------------
# Container Registry (OCIR)
# ---------------------------------------------------------------------------

output "ocir_image_uri" {
  description = "OCIR image URI (without tag) — append :latest or :v1.0.0. Maps to config.container_image"
  value       = local.ocir_image_uri
}

output "ocir_login_server" {
  description = "OCIR login server for docker login"
  value       = "${local.region_key}.ocir.io"
}

output "ocir_docker_login_command" {
  description = "Docker login command template (replace <username> and <auth_token>)"
  value       = "docker login ${local.region_key}.ocir.io -u ${local.namespace}/<username> -p <auth_token>"
  sensitive   = false
}

# ---------------------------------------------------------------------------
# Container Instance sizing
# ---------------------------------------------------------------------------

output "instance_shape" {
  description = "Container Instance shape — maps to config.instance_shape"
  value       = var.instance_shape
}

output "instance_ocpus" {
  description = "OCPUs per instance — maps to config.instance_ocpus"
  value       = var.instance_ocpus
}

output "instance_memory_gb" {
  description = "Memory GB per instance — maps to config.instance_memory_gb"
  value       = var.instance_memory_gb
}

# ---------------------------------------------------------------------------
# IAM
# ---------------------------------------------------------------------------

output "dynamic_group_name" {
  description = "Dynamic Group name for container instances"
  value       = oci_identity_dynamic_group.container_instances.name
}

output "dynamic_group_id" {
  description = "Dynamic Group OCID"
  value       = oci_identity_dynamic_group.container_instances.id
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

output "vcn_id" {
  description = "VCN OCID"
  value       = oci_core_vcn.this.id
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

output "log_group_id" {
  description = "Log Group OCID for container instance logs"
  value       = oci_logging_log_group.this.id
}

# ---------------------------------------------------------------------------
# Scheduler Compute Instance
# ---------------------------------------------------------------------------

output "ssh_private_key_path" {
  description = "Configured SSH private key path for helper scripts"
  value       = var.ssh_private_key_path
}

output "scheduler_instance_id" {
  description = "Scheduler compute instance OCID"
  value       = var.create_scheduler_instance ? oci_core_instance.scheduler[0].id : null
}

output "scheduler_private_ip" {
  description = "Private IP of the scheduler instance (used by workers in the same VCN)"
  value       = var.create_scheduler_instance ? oci_core_instance.scheduler[0].private_ip : null
}

output "scheduler_public_ip" {
  description = "Public IP of the scheduler instance (only if using public subnet)"
  value       = var.create_scheduler_instance ? oci_core_instance.scheduler[0].public_ip : null
}

output "scheduler_address" {
  description = "Scheduler address for workers (tcp://<private_ip>:<port>)"
  value       = var.create_scheduler_instance ? "tcp://${oci_core_instance.scheduler[0].private_ip}:${var.scheduler_port}" : null
}

output "scheduler_ssh_command" {
  description = "SSH command to connect to the scheduler instance"
  value       = var.create_scheduler_instance && oci_core_instance.scheduler[0].public_ip != "" ? "ssh opc@${oci_core_instance.scheduler[0].public_ip}" : null
}

# ---------------------------------------------------------------------------
# Bastion Host
# ---------------------------------------------------------------------------

output "bastion_public_ip" {
  description = "Public IP of the bastion host"
  value       = var.create_bastion ? oci_core_instance.bastion[0].public_ip : null
}

output "bastion_ssh_command" {
  description = "SSH command to connect to the bastion"
  value       = var.create_bastion ? "ssh -i ${var.ssh_private_key_path} opc@${oci_core_instance.bastion[0].public_ip}" : null
}

output "bastion_tunnel_to_scheduler" {
  description = "SSH tunnel command to forward the scheduler port through the bastion"
  value = var.create_bastion && var.create_scheduler_instance ? join(" ", [
    "ssh -i ${var.ssh_private_key_path}",
    "-o 'ProxyCommand=ssh -i ${var.ssh_private_key_path} -W %h:%p opc@${oci_core_instance.bastion[0].public_ip}'",
    "-L ${var.scheduler_port}:localhost:${var.scheduler_port}",
    "opc@${oci_core_instance.scheduler[0].private_ip} -N"
  ]) : null
}

output "bastion_ssh_to_scheduler" {
  description = "SSH to scheduler through bastion"
  value = var.create_bastion && var.create_scheduler_instance ? join(" ", [
    "ssh -i ${var.ssh_private_key_path}",
    "-o 'ProxyCommand=ssh -i ${var.ssh_private_key_path} -W %h:%p opc@${oci_core_instance.bastion[0].public_ip}'",
    "opc@${oci_core_instance.scheduler[0].private_ip}"
  ]) : null
}

# ---------------------------------------------------------------------------
# Build & Push helper
# ---------------------------------------------------------------------------

output "build_and_push_command" {
  description = "Command to build and push the HPC worker image to OCIR"
  value       = "./scripts/build-and-push.sh --scaler-src <path-to-scaler> --ocir-uri ${local.ocir_image_uri} --adapter hpc"
}

output "deploy_scheduler_command" {
  description = "Command to deploy local scaler source to the scheduler instance"
  value = var.create_bastion && var.create_scheduler_instance ? join(" ", [
    "./scripts/deploy-scheduler.sh",
    "--scaler-src <path-to-scaler>",
    "--bastion-ip ${oci_core_instance.bastion[0].public_ip}",
    "--scheduler-ip ${oci_core_instance.scheduler[0].private_ip}",
    "--ssh-key ${var.ssh_private_key_path}",
  ]) : null
}

# ---------------------------------------------------------------------------
# Provisioner-compatible JSON config
#
# Can be saved as .scaler_oci_config.json and loaded by the test harness:
#   terraform output -json scaler_config > .scaler_oci_config.json
# ---------------------------------------------------------------------------

output "scaler_config" {
  description = "JSON config compatible with OCIProvisioner.save_config() and the test harness"
  value = {
    oci_region               = var.region
    tenancy_id               = var.tenancy_ocid
    compartment_id           = var.compartment_ocid
    prefix                   = local.prefix
    object_storage_namespace = local.namespace
    object_storage_bucket    = oci_objectstorage_bucket.this.name
    object_storage_prefix    = var.object_storage_prefix
    container_image          = "${local.ocir_image_uri}:latest"
    availability_domain      = local.availability_domain
    subnet_id                = oci_core_subnet.this.id
    instance_shape           = var.instance_shape
    instance_ocpus           = var.instance_ocpus
    instance_memory_gb       = var.instance_memory_gb
    dynamic_group_name       = oci_identity_dynamic_group.container_instances.name
    iam_policy_name          = oci_identity_policy.object_storage_access.name
    scheduler_address        = var.create_scheduler_instance ? "tcp://${oci_core_instance.scheduler[0].private_ip}:${var.scheduler_port}" : null
  }
}
