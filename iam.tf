##############################################################################
# IAM — Dynamic Group & Policies
#
# Container Instances need Resource Principal auth to access:
#   - Object Storage (read/write task payloads and results)
#
# The Dynamic Group matches all container instances in the compartment.
# The Policy grants the dynamic group object-level access to the bucket.
##############################################################################

# ---------------------------------------------------------------------------
# Dynamic Group
# ---------------------------------------------------------------------------

resource "oci_identity_dynamic_group" "container_instances" {
  provider       = oci.home
  compartment_id = var.tenancy_ocid # dynamic groups live at tenancy level
  name           = "${local.prefix}-ci-dg"
  description    = "Scaler OCI Container Instances in compartment ${var.compartment_ocid}"

  matching_rule = join("", [
    "ALL {",
    "resource.type='computecontainerinstance', ",
    "resource.compartment.id='${var.compartment_ocid}'",
    "}"
  ])
}

# ---------------------------------------------------------------------------
# IAM Policy — Object Storage access
# ---------------------------------------------------------------------------

resource "oci_identity_policy" "object_storage_access" {
  provider       = oci.home
  compartment_id = var.compartment_ocid
  name           = "${local.prefix}-ci-os-policy"
  description    = "Allow Scaler container instances to read/write task data in Object Storage"

  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.container_instances.name} to manage objects in compartment id ${var.compartment_ocid} where target.bucket.name='${oci_objectstorage_bucket.this.name}'",
    "Allow dynamic-group ${oci_identity_dynamic_group.container_instances.name} to read buckets in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group ${oci_identity_dynamic_group.container_instances.name} to use virtual-network-family in compartment id ${var.compartment_ocid}",
  ]
}

# ---------------------------------------------------------------------------
# Dynamic Group — Scheduler Instance (for instance principal auth)
# ---------------------------------------------------------------------------

resource "oci_identity_dynamic_group" "scheduler" {
  count = var.create_scheduler_instance ? 1 : 0

  provider       = oci.home
  compartment_id = var.tenancy_ocid
  name           = "${local.prefix}-scheduler-dg"
  description    = "Scaler scheduler compute instance"

  matching_rule = "ALL {instance.id='${oci_core_instance.scheduler[0].id}'}"
}

# ---------------------------------------------------------------------------
# IAM Policy — Scheduler: manage container instances, pull from OCIR, read networking
# ---------------------------------------------------------------------------

resource "oci_identity_policy" "scheduler_instance_principal" {
  count = var.create_scheduler_instance ? 1 : 0

  provider       = oci.home
  compartment_id = var.compartment_ocid
  name           = "${local.prefix}-scheduler-policy"
  description    = "Allow scheduler instance to manage container instances, pull images, and read networking"

  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.scheduler[0].name} to manage compute-container-family in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group ${oci_identity_dynamic_group.scheduler[0].name} to manage repos in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group ${oci_identity_dynamic_group.scheduler[0].name} to manage virtual-network-family in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group ${oci_identity_dynamic_group.scheduler[0].name} to manage objects in compartment id ${var.compartment_ocid} where target.bucket.name='${oci_objectstorage_bucket.this.name}'",
    "Allow dynamic-group ${oci_identity_dynamic_group.scheduler[0].name} to read buckets in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group ${oci_identity_dynamic_group.scheduler[0].name} to use log-content in compartment id ${var.compartment_ocid}",
  ]
}

# ---------------------------------------------------------------------------
# IAM Policy — Container Instance log access (if logging is enabled)
# ---------------------------------------------------------------------------

resource "oci_identity_policy" "logging_access" {
  provider       = oci.home
  compartment_id = var.compartment_ocid
  name           = "${local.prefix}-ci-log-policy"
  description    = "Allow Scaler container instances to write logs"

  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.container_instances.name} to use log-content in compartment id ${var.compartment_ocid}",
  ]
}
