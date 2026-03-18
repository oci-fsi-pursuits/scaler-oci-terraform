##############################################################################
# Logging — Log Group and Custom Log for Container Instances
#
# Captures stdout/stderr from container instances for debugging failed tasks.
# The oci_hpc task manager's _fetch_instance_logs() queries this via the
# OCI Logging Search API.
##############################################################################

resource "oci_logging_log_group" "this" {
  compartment_id = var.compartment_ocid
  display_name   = "${local.prefix}-logs"
  description    = "Scaler OCI Container Instance logs"
}

resource "oci_logging_log" "container_instances" {
  display_name = "${local.prefix}-ci-log"
  log_group_id = oci_logging_log_group.this.id
  log_type     = "CUSTOM"
  is_enabled   = true

  retention_duration = 30
}
