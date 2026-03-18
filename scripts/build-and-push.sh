#!/usr/bin/env bash
##############################################################################
# Build and push Scaler OCI worker container images to OCIR.
#
# Usage:
#   ./scripts/build-and-push.sh --scaler-src ../opengris-scaler-oci \
#                                --ocir-uri phx.ocir.io/mytenancy/scaler-worker \
#                                --tag latest \
#                                --adapter hpc   # or "raw" or "both"
#
# Prerequisites:
#   - Docker installed and running
#   - Authenticated to OCIR:
#       docker login <region>.ocir.io -u <namespace>/<user> -p <auth_token>
#   - Terraform outputs available (or pass values directly)
#
# You can also source values from Terraform:
#   OCIR_URI=$(terraform output -raw ocir_image_uri)
#   ./scripts/build-and-push.sh --scaler-src ../opengris-scaler-oci \
#                                --ocir-uri "$OCIR_URI" --adapter both
##############################################################################
set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
SCALER_SRC=""
OCIR_URI=""
TAG="latest"
ADAPTER="hpc"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
usage() {
    echo "Usage: $0 --scaler-src <path> --ocir-uri <uri> [--tag <tag>] [--adapter hpc|raw|both]"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scaler-src)  SCALER_SRC="$2";  shift 2 ;;
        --ocir-uri)    OCIR_URI="$2";    shift 2 ;;
        --tag)         TAG="$2";         shift 2 ;;
        --adapter)     ADAPTER="$2";     shift 2 ;;
        -h|--help)     usage ;;
        *)             echo "Unknown argument: $1"; usage ;;
    esac
done

if [[ -z "$SCALER_SRC" || -z "$OCIR_URI" ]]; then
    echo "ERROR: --scaler-src and --ocir-uri are required."
    usage
fi

# Resolve to absolute path
SCALER_SRC="$(cd "$SCALER_SRC" && pwd)"

if [[ ! -d "$SCALER_SRC/src/scaler" ]]; then
    echo "ERROR: $SCALER_SRC does not look like the scaler source tree (missing src/scaler/)."
    exit 1
fi

# ---------------------------------------------------------------------------
# Build functions
# ---------------------------------------------------------------------------

build_hpc() {
    local dockerfile="$SCALER_SRC/src/scaler/worker_manager_adapter/oci_hpc/utility/Dockerfile.container_instance"
    local image="${OCIR_URI}-hpc:${TAG}"

    if [[ ! -f "$dockerfile" ]]; then
        echo "ERROR: HPC Dockerfile not found at $dockerfile"
        exit 1
    fi

    echo "============================================================"
    echo "Building OCI HPC worker image"
    echo "  Dockerfile: $dockerfile"
    echo "  Image:      $image"
    echo "============================================================"

    # Build from the src/ directory so COPY paths resolve correctly
    docker build \
        -f "$dockerfile" \
        -t "$image" \
        "$SCALER_SRC/src"

    echo ""
    echo "Pushing $image ..."
    docker push "$image"
    echo "Done: $image"
    echo ""
}

build_raw() {
    local dockerfile="$SCALER_SRC/src/scaler/worker_manager_adapter/oci_raw/utility/Dockerfile.container_instance"
    local image="${OCIR_URI}-raw:${TAG}"

    if [[ ! -f "$dockerfile" ]]; then
        echo "ERROR: Raw Dockerfile not found at $dockerfile"
        exit 1
    fi

    echo "============================================================"
    echo "Building OCI Raw worker image"
    echo "  Dockerfile: $dockerfile"
    echo "  Image:      $image"
    echo "============================================================"

    # Build from the src/ directory so COPY paths resolve correctly
    docker build \
        -f "$dockerfile" \
        -t "$image" \
        "$SCALER_SRC/src"

    echo ""
    echo "Pushing $image ..."
    docker push "$image"
    echo "Done: $image"
    echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

case "$ADAPTER" in
    hpc)  build_hpc ;;
    raw)  build_raw ;;
    both) build_hpc; build_raw ;;
    *)    echo "ERROR: --adapter must be hpc, raw, or both"; exit 1 ;;
esac

echo "============================================================"
echo "All images built and pushed successfully."
echo "============================================================"
