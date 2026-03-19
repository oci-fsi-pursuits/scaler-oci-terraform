##############################################################################
# Object Storage — Bucket for task payloads and results
#
# The oci_hpc adapter stores:
#   {prefix}/inputs/{task_id}.pkl[.gz]  — serialized function + arguments
#   {prefix}/results/{task_id}.pkl      — serialized result
#
# A lifecycle rule auto-deletes objects after var.bucket_lifecycle_days to
# prevent stale data from accumulating.
##############################################################################

resource "oci_objectstorage_bucket" "this" {
  compartment_id = var.compartment_ocid
  namespace      = local.namespace
  name           = "${local.prefix}-${local.namespace}-${var.region}"
  access_type    = "NoPublicAccess"

  # Enable versioning for safety (can be disabled for cost savings)
  versioning = "Disabled"
}

# ---------------------------------------------------------------------------
# Lifecycle rule — auto-delete task objects after N days
# ---------------------------------------------------------------------------

resource "oci_objectstorage_object_lifecycle_policy" "cleanup" {
  namespace = local.namespace
  bucket    = oci_objectstorage_bucket.this.name

  rules {
    name        = "cleanup-old-tasks"
    action      = "DELETE"
    time_amount = var.bucket_lifecycle_days
    time_unit   = "DAYS"
    is_enabled  = true

    object_name_filter {
      inclusion_prefixes = ["${var.object_storage_prefix}/"]
    }
  }
}
