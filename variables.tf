##############################################################################
# Variables
##############################################################################

# ---------------------------------------------------------------------------
# OCI Provider Authentication
# ---------------------------------------------------------------------------

variable "tenancy_ocid" {
  description = "OCID of the OCI tenancy."
  type        = string
}

variable "user_ocid" {
  description = "OCID of the OCI user for API key authentication."
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint of the API signing key."
  type        = string
}

variable "private_key_path" {
  description = "Path to the PEM private key used for OCI API authentication."
  type        = string
}

variable "region" {
  description = "OCI region identifier (e.g. us-ashburn-1)."
  type        = string
  default     = "us-ashburn-1"
}

variable "compartment_ocid" {
  description = "OCID of the compartment where all resources will be created."
  type        = string
}

# ---------------------------------------------------------------------------
# Naming
# ---------------------------------------------------------------------------

variable "resource_prefix" {
  description = "Prefix applied to all resource names for easy identification."
  type        = string
  default     = "scaler"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "vcn_cidr" {
  description = "CIDR block for the VCN."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the container instances subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_domain" {
  description = "Availability domain name. Leave empty to use the first AD in the region."
  type        = string
  default     = ""
}

variable "create_nat_gateway" {
  description = "Create a NAT gateway for private subnet egress. Set to false if using a public subnet."
  type        = bool
  default     = true
}

variable "use_public_subnet" {
  description = "If true, the subnet gets an internet gateway and containers receive public IPs. If false, uses NAT gateway for egress only."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Container Instance Sizing (defaults match the Scaler adapter)
# ---------------------------------------------------------------------------

variable "instance_shape" {
  description = "OCI Container Instance shape."
  type        = string
  default     = "CI.Standard.E4.Flex"
}

variable "instance_ocpus" {
  description = "Number of OCPUs per container instance."
  type        = number
  default     = 4.0
}

variable "instance_memory_gb" {
  description = "Memory in GB per container instance."
  type        = number
  default     = 30.0
}

# ---------------------------------------------------------------------------
# Object Storage
# ---------------------------------------------------------------------------

variable "object_storage_prefix" {
  description = "Key prefix inside the Object Storage bucket for task data."
  type        = string
  default     = "scaler-tasks"
}

variable "bucket_lifecycle_days" {
  description = "Number of days after which task objects are auto-deleted."
  type        = number
  default     = 1
}

# ---------------------------------------------------------------------------
# Container Registry (OCIR)
# ---------------------------------------------------------------------------

variable "create_ocir_repository" {
  description = "Whether to create an OCIR repository for the worker container image."
  type        = bool
  default     = true
}

variable "ocir_repository_is_public" {
  description = "Whether the OCIR repository should be public."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Scheduler connectivity
# ---------------------------------------------------------------------------

variable "scheduler_port" {
  description = "TCP port the Scaler scheduler listens on. Used in security list egress rules."
  type        = number
  default     = 2345
}

variable "scheduler_cidr" {
  description = "CIDR of the scheduler host(s). Use 0.0.0.0/0 if the scheduler is outside OCI."
  type        = string
  default     = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# Scheduler Compute Instance (optional)
# ---------------------------------------------------------------------------

variable "create_scheduler_instance" {
  description = "Whether to create a compute instance to run the Scaler scheduler."
  type        = bool
  default     = false
}

variable "scheduler_instance_shape" {
  description = "Shape for the scheduler compute instance."
  type        = string
  default     = "VM.Standard.E4.Flex"
}

variable "scheduler_instance_ocpus" {
  description = "OCPUs for the scheduler compute instance (Flex shapes only)."
  type        = number
  default     = 1.0
}

variable "scheduler_instance_memory_gb" {
  description = "Memory in GB for the scheduler compute instance (Flex shapes only)."
  type        = number
  default     = 8.0
}

variable "scheduler_ssh_public_key" {
  description = "SSH public key for the scheduler instance. Required if create_scheduler_instance is true."
  type        = string
  default     = ""
}

variable "scheduler_workers_per_instance" {
  description = "Number of workers per container instance (passed to scaler_cluster)."
  type        = number
  default     = 4
}

variable "scaler_pip_package" {
  description = "pip package spec to install scaler on the scheduler instance (e.g. 'opengris-scaler' or 'git+https://...')."
  type        = string
  default     = "opengris-scaler"
}

# ---------------------------------------------------------------------------
# Bastion Host (optional)
# ---------------------------------------------------------------------------

variable "create_bastion" {
  description = "Whether to create a bastion host for SSH access to private resources."
  type        = bool
  default     = false
}

variable "bastion_shape" {
  description = "Shape for the bastion compute instance."
  type        = string
  default     = "VM.Standard.E4.Flex"
}

variable "bastion_ocpus" {
  description = "OCPUs for the bastion instance (Flex shapes only)."
  type        = number
  default     = 1.0
}

variable "bastion_memory_gb" {
  description = "Memory in GB for the bastion instance (Flex shapes only)."
  type        = number
  default     = 4.0
}

variable "bastion_subnet_cidr" {
  description = "CIDR block for the bastion public subnet."
  type        = string
  default     = "10.0.2.0/24"
}

variable "bastion_ssh_cidr" {
  description = "CIDR allowed to SSH to the bastion. Use your IP/32 for security, or 0.0.0.0/0 for open access."
  type        = string
  default     = "0.0.0.0/0"
}

variable "bastion_ssh_public_key" {
  description = "SSH public key for the bastion. If empty, uses scheduler_ssh_public_key."
  type        = string
  default     = ""
}
