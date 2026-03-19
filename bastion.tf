##############################################################################
# Bastion Host
#
# A small public-facing compute instance for SSH access to private resources
# (scheduler, container instances) in the VCN.
#
# Set  var.create_bastion = true  to provision this.
#
# Usage:
#   # Direct SSH to bastion:
#   ssh -i ~/.ssh/scaler_scheduler opc@<bastion_public_ip>
#
#   # SSH tunnel to scheduler:
#   ssh -i ~/.ssh/scaler_scheduler -L 2345:<scheduler_private_ip>:2345 \
#       opc@<bastion_public_ip> -N
#
#   # Then connect locally:
#   python harness.py --scheduler tcp://127.0.0.1:2345
##############################################################################

# ---------------------------------------------------------------------------
# Public subnet for the bastion (separate from the private worker subnet)
# ---------------------------------------------------------------------------

resource "oci_core_internet_gateway" "bastion" {
  count = var.create_bastion ? 1 : 0

  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.prefix}-bastion-igw"
  enabled        = true
}

resource "oci_core_route_table" "bastion" {
  count = var.create_bastion ? 1 : 0

  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.prefix}-bastion-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.bastion[0].id
  }
}

resource "oci_core_security_list" "bastion" {
  count = var.create_bastion ? 1 : 0

  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.prefix}-bastion-sl"

  # SSH ingress
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = var.bastion_ssh_cidr
    description = "SSH access to bastion"

    tcp_options {
      min = 22
      max = 22
    }
  }

  # ICMP for path MTU discovery
  ingress_security_rules {
    protocol  = "1" # ICMP
    source    = "0.0.0.0/0"
    stateless = false
  }

  # All egress (bastion needs to reach private subnet)
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    description = "Allow all egress"
  }
}

resource "oci_core_subnet" "bastion" {
  count = var.create_bastion ? 1 : 0

  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.this.id
  display_name               = "${local.prefix}-bastion-subnet"
  cidr_block                 = var.bastion_subnet_cidr
  availability_domain        = local.availability_domain
  prohibit_public_ip_on_vnic = false
  route_table_id             = oci_core_route_table.bastion[0].id
  security_list_ids          = [oci_core_security_list.bastion[0].id]
  dns_label                  = "bastion"
}

# ---------------------------------------------------------------------------
# Latest Oracle Linux 8 image for bastion
# ---------------------------------------------------------------------------

data "oci_core_images" "bastion" {
  count = var.create_bastion ? 1 : 0

  compartment_id           = var.compartment_ocid
  operating_system         = "Oracle Linux"
  operating_system_version = "8"
  shape                    = var.bastion_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# ---------------------------------------------------------------------------
# Bastion Compute Instance
# ---------------------------------------------------------------------------

resource "oci_core_instance" "bastion" {
  count = var.create_bastion ? 1 : 0

  compartment_id      = var.compartment_ocid
  availability_domain = local.availability_domain
  display_name        = "${local.prefix}-bastion"
  shape               = var.bastion_shape

  dynamic "shape_config" {
    for_each = length(regexall("Flex$", var.bastion_shape)) > 0 ? [1] : []
    content {
      ocpus         = var.bastion_ocpus
      memory_in_gbs = var.bastion_memory_gb
    }
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.bastion[0].images[0].id
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.bastion[0].id
    assign_public_ip = true
    display_name     = "${local.prefix}-bastion-vnic"
  }

  metadata = {
    ssh_authorized_keys = var.bastion_ssh_public_key != "" ? var.bastion_ssh_public_key : local.resolved_ssh_public_key
  }

  lifecycle {
    precondition {
      condition     = var.bastion_ssh_public_key != "" || local.resolved_ssh_public_key != ""
      error_message = "An SSH public key is required. Set bastion_ssh_public_key, scheduler_ssh_public_key, or ssh_public_key_file."
    }
  }

  freeform_tags = {
    "scaler-role" = "bastion"
    "prefix"      = local.prefix
  }
}

# ---------------------------------------------------------------------------
# Allow bastion subnet to reach the private worker subnet
# (Add ingress rule to the worker security list)
# ---------------------------------------------------------------------------

resource "oci_core_security_list" "bastion_to_workers" {
  count = var.create_bastion ? 1 : 0

  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.prefix}-bastion-to-workers-sl"

  # Allow SSH from bastion subnet to worker subnet
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = var.bastion_subnet_cidr
    description = "SSH from bastion"

    tcp_options {
      min = 22
      max = 22
    }
  }

  # Allow bastion to reach scheduler port
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = var.bastion_subnet_cidr
    description = "Scheduler port from bastion"

    tcp_options {
      min = var.scheduler_port
      max = var.scheduler_port
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    description = "Allow all egress"
  }
}
