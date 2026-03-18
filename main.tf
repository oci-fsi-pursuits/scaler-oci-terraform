##############################################################################
# Scaler OCI Infrastructure — Provider & Data Sources
#
# Provisions all OCI prerequisites for the OpenGRIS Scaler worker manager
# adapters (oci_raw and oci_hpc).
##############################################################################

terraform {
  required_version = ">= 1.5"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Default provider — target region for infrastructure resources
# (VCN, subnet, Object Storage, Container Instances, OCIR, logging)
# ---------------------------------------------------------------------------

provider "oci" {
  region           = var.region
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
}

# ---------------------------------------------------------------------------
# Home region provider — required for IAM resources
#
# OCI mandates that Dynamic Groups and IAM Policies are created in the
# tenancy's home region, regardless of where the workload runs.
# ---------------------------------------------------------------------------

provider "oci" {
  alias            = "home"
  region           = local.home_region
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
}

# ---------------------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------------------

data "oci_identity_tenancy" "this" {
  tenancy_id = var.tenancy_ocid
}

# Look up all subscribed regions to find the home region key → name mapping
data "oci_identity_region_subscriptions" "this" {
  tenancy_id = var.tenancy_ocid
}

data "oci_identity_availability_domains" "this" {
  compartment_id = var.tenancy_ocid
}

data "oci_objectstorage_namespace" "this" {
  compartment_id = var.compartment_ocid
}

locals {
  # Derive the home region from the tenancy's subscribed regions
  home_region = [
    for r in data.oci_identity_region_subscriptions.this.region_subscriptions :
    r.region_name if r.is_home_region
  ][0]

  # Pick the requested AD or default to the first one
  availability_domain = var.availability_domain != "" ? var.availability_domain : data.oci_identity_availability_domains.this.availability_domains[0].name
  namespace           = data.oci_objectstorage_namespace.this.namespace
  prefix              = var.resource_prefix
}
