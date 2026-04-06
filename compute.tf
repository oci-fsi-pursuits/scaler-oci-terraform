##############################################################################
# Compute — Scheduler Instance
#
# A small compute instance that runs the Scaler scheduler.  Container
# Instance workers in the same subnet connect back to this host.
#
# Set  var.create_scheduler_instance = true  to provision this.
##############################################################################

# ---------------------------------------------------------------------------
# Latest Oracle Linux 8 image
# ---------------------------------------------------------------------------

data "oci_core_images" "oracle_linux" {
  count = var.create_scheduler_instance ? 1 : 0

  compartment_id           = var.compartment_ocid
  operating_system         = "Oracle Linux"
  operating_system_version = "8"
  shape                    = var.scheduler_instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# ---------------------------------------------------------------------------
# Cloud-init
# ---------------------------------------------------------------------------

data "cloudinit_config" "scheduler" {
  count = var.create_scheduler_instance ? 1 : 0

  gzip          = true
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/scripts/cloud-init-scheduler.yaml", {
      scheduler_port      = var.scheduler_port
      scheduler_workers   = var.scheduler_workers_per_instance
      container_image     = "${local.ocir_image_uri}-raw:latest"
      compartment_id      = var.compartment_ocid
      availability_domain = local.availability_domain
      subnet_id           = oci_core_subnet.this.id
      instance_shape      = var.instance_shape
      instance_ocpus      = var.instance_ocpus
      instance_memory_gb  = var.instance_memory_gb
      os_namespace        = local.namespace
      os_bucket           = oci_objectstorage_bucket.this.name
      os_prefix           = var.object_storage_prefix
      scaler_package      = var.scaler_pip_package
      oci_region          = var.region
    })
  }
}

# ---------------------------------------------------------------------------
# Compute Instance
# ---------------------------------------------------------------------------

resource "oci_core_instance" "scheduler" {
  count = var.create_scheduler_instance ? 1 : 0

  compartment_id      = var.compartment_ocid
  availability_domain = local.availability_domain
  display_name        = "${local.prefix}-scheduler"
  shape               = var.scheduler_instance_shape

  dynamic "shape_config" {
    for_each = length(regexall("Flex$", var.scheduler_instance_shape)) > 0 ? [1] : []
    content {
      ocpus         = var.scheduler_instance_ocpus
      memory_in_gbs = var.scheduler_instance_memory_gb
    }
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.oracle_linux[0].images[0].id
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.this.id
    assign_public_ip = var.use_public_subnet
    display_name     = "${local.prefix}-scheduler-vnic"
  }

  metadata = {
    ssh_authorized_keys = local.resolved_ssh_public_key
    user_data           = data.cloudinit_config.scheduler[0].rendered
  }

  lifecycle {
    precondition {
      condition     = local.resolved_ssh_public_key != ""
      error_message = "An SSH public key is required. Set scheduler_ssh_public_key or ssh_public_key_file."
    }
  }

  freeform_tags = {
    "scaler-role" = "scheduler"
    "prefix"      = local.prefix
  }
}

# ---------------------------------------------------------------------------
# Security List rule — allow container instances to reach the scheduler
# (The main security list already allows all egress; we need an ingress rule
#  on the scheduler port from the subnet CIDR.)
# ---------------------------------------------------------------------------

resource "oci_core_security_list" "scheduler" {
  count = var.create_scheduler_instance ? 1 : 0

  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.prefix}-scheduler-sl"

  ingress_security_rules {
    protocol    = "6" # TCP
    source      = var.subnet_cidr
    description = "Allow workers to reach scheduler"

    tcp_options {
      min = var.scheduler_port
      max = var.scheduler_port
    }
  }

  # Workers inside Container Instances connect to the object storage server
  # (scheduler_port + 1) to fetch/store serialized function objects
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = var.subnet_cidr
    description = "Allow workers to reach object storage server"

    tcp_options {
      min = var.scheduler_port + 1
      max = var.scheduler_port + 1
    }
  }

  # Allow SSH from anywhere (for management)
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    description = "SSH access"

    tcp_options {
      min = 22
      max = 22
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    description = "Allow all egress"
  }
}
