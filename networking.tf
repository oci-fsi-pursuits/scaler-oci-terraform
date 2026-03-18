##############################################################################
# Networking — VCN, Gateways, Route Tables, Security List, Subnet
#
# Container Instances need:
#   - Egress to the Scaler scheduler (TCP, var.scheduler_port)
#   - Egress to OCI Object Storage (HTTPS / port 443)
#   - Egress to OCIR to pull the container image (HTTPS / port 443)
#
# Two modes:
#   use_public_subnet = true  → Internet Gateway, public IPs on containers
#   use_public_subnet = false → NAT Gateway, no public IPs (recommended)
##############################################################################

# ---------------------------------------------------------------------------
# VCN
# ---------------------------------------------------------------------------

resource "oci_core_vcn" "this" {
  compartment_id = var.compartment_ocid
  display_name   = "${local.prefix}-vcn"
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = replace(local.prefix, "-", "")
}

# ---------------------------------------------------------------------------
# Internet Gateway (public subnet mode)
# ---------------------------------------------------------------------------

resource "oci_core_internet_gateway" "this" {
  count = var.use_public_subnet ? 1 : 0

  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.prefix}-igw"
  enabled        = true
}

# ---------------------------------------------------------------------------
# NAT Gateway (private subnet mode)
# ---------------------------------------------------------------------------

resource "oci_core_nat_gateway" "this" {
  count = var.create_nat_gateway && !var.use_public_subnet ? 1 : 0

  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.prefix}-natgw"
}

# ---------------------------------------------------------------------------
# Service Gateway (OCI services — Object Storage, OCIR)
# ---------------------------------------------------------------------------

data "oci_core_services" "all" {}

locals {
  # "All <region> Services In Oracle Services Network"
  all_services = [
    for s in data.oci_core_services.all.services :
    s if can(regex("All .* Services In Oracle Services Network", s.name))
  ]
  service_id = length(local.all_services) > 0 ? local.all_services[0].id : ""
}

resource "oci_core_service_gateway" "this" {
  count = local.service_id != "" ? 1 : 0

  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.prefix}-sgw"

  services {
    service_id = local.service_id
  }
}

# ---------------------------------------------------------------------------
# Route Table
# ---------------------------------------------------------------------------

resource "oci_core_route_table" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.prefix}-rt"

  # Internet / NAT gateway route for general egress
  dynamic "route_rules" {
    for_each = var.use_public_subnet && length(oci_core_internet_gateway.this) > 0 ? [1] : []
    content {
      destination       = "0.0.0.0/0"
      destination_type  = "CIDR_BLOCK"
      network_entity_id = oci_core_internet_gateway.this[0].id
    }
  }

  dynamic "route_rules" {
    for_each = !var.use_public_subnet && length(oci_core_nat_gateway.this) > 0 ? [1] : []
    content {
      destination       = "0.0.0.0/0"
      destination_type  = "CIDR_BLOCK"
      network_entity_id = oci_core_nat_gateway.this[0].id
    }
  }

  # Service gateway route for OCI services (Object Storage, OCIR)
  dynamic "route_rules" {
    for_each = length(oci_core_service_gateway.this) > 0 ? [1] : []
    content {
      destination       = local.all_services[0].cidr_block
      destination_type  = "SERVICE_CIDR_BLOCK"
      network_entity_id = oci_core_service_gateway.this[0].id
    }
  }
}

# ---------------------------------------------------------------------------
# Security List
# ---------------------------------------------------------------------------

resource "oci_core_security_list" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.prefix}-sl"

  # Egress: allow all outbound (container instances need to reach scheduler,
  # Object Storage, and OCIR)
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "6" # TCP
    stateless   = false

    tcp_options {
      min = 1
      max = 65535
    }
  }

  # Ingress: allow responses (stateful rules handle return traffic).
  # No explicit ingress needed — containers initiate all connections.

  # Ingress: ICMP for path MTU discovery
  ingress_security_rules {
    source    = var.vcn_cidr
    protocol  = "1" # ICMP
    stateless = false
  }
}

# ---------------------------------------------------------------------------
# Subnet
# ---------------------------------------------------------------------------

resource "oci_core_subnet" "this" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.this.id
  display_name               = "${local.prefix}-subnet"
  cidr_block                 = var.subnet_cidr
  availability_domain        = local.availability_domain
  prohibit_public_ip_on_vnic = !var.use_public_subnet
  route_table_id             = oci_core_route_table.this.id
  security_list_ids = concat(
    [oci_core_security_list.this.id],
    var.create_bastion ? [oci_core_security_list.bastion_to_workers[0].id] : [],
    var.create_scheduler_instance ? [oci_core_security_list.scheduler[0].id] : [],
  )
  dns_label = "workers"
}
