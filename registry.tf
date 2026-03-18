##############################################################################
# Container Registry (OCIR) — Repository for the worker container image
#
# Image URI format: <region>.ocir.io/<namespace>/<repo-name>:<tag>
# e.g. iad.ocir.io/mytenancy/scaler-worker:latest
#
# Docker login:
#   docker login <region>.ocir.io \
#     -u <namespace>/<username> \
#     -p <auth_token>
##############################################################################

resource "oci_artifacts_container_repository" "worker" {
  count = var.create_ocir_repository ? 1 : 0

  compartment_id = var.compartment_ocid
  display_name   = "${local.prefix}-worker"
  is_public      = var.ocir_repository_is_public
}

locals {
  # Derive the region key for the OCIR URL (e.g. "us-ashburn-1" → "iad")
  # OCI region keys: https://docs.oracle.com/en-us/iaas/Content/Registry/Concepts/registryprerequisites.htm
  region_key_map = {
    "us-ashburn-1"    = "iad"
    "us-phoenix-1"    = "phx"
    "us-sanjose-1"    = "sjc"
    "us-chicago-1"    = "ord"
    "ca-toronto-1"    = "yyz"
    "ca-montreal-1"   = "yul"
    "eu-frankfurt-1"  = "fra"
    "eu-amsterdam-1"  = "ams"
    "eu-zurich-1"     = "zrh"
    "eu-marseille-1"  = "mrs"
    "eu-milan-1"      = "lin"
    "eu-stockholm-1"  = "arn"
    "eu-paris-1"      = "cdg"
    "uk-london-1"     = "lhr"
    "uk-cardiff-1"    = "cwl"
    "ap-tokyo-1"      = "nrt"
    "ap-osaka-1"      = "kix"
    "ap-sydney-1"     = "syd"
    "ap-melbourne-1"  = "mel"
    "ap-mumbai-1"     = "bom"
    "ap-hyderabad-1"  = "hyd"
    "ap-seoul-1"      = "icn"
    "ap-chuncheon-1"  = "yny"
    "ap-singapore-1"  = "sin"
    "sa-saopaulo-1"   = "gru"
    "sa-santiago-1"   = "scl"
    "sa-vinhedo-1"    = "vcp"
    "me-jeddah-1"     = "jed"
    "me-dubai-1"      = "dxb"
    "af-johannesburg-1" = "jnb"
    "il-jerusalem-1"  = "mtz"
  }

  region_key     = lookup(local.region_key_map, var.region, var.region)
  ocir_repo_name = var.create_ocir_repository ? oci_artifacts_container_repository.worker[0].display_name : "${local.prefix}-worker"
  ocir_image_uri = "${local.region_key}.ocir.io/${local.namespace}/${local.ocir_repo_name}"
}
