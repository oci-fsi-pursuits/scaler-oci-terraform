#!/usr/bin/env bash
##############################################################################
# Deploy the local scaler source to the scheduler instance and start it.
#
# Usage:
#   ./scripts/deploy-scheduler.sh \
#       --scaler-src ../opengris-scaler-oci \
#       --bastion-ip <bastion_public_ip> \
#       --scheduler-ip <scheduler_private_ip>
#
# Or using Terraform outputs:
#   ./scripts/deploy-scheduler.sh \
#       --scaler-src ../opengris-scaler-oci \
#       --bastion-ip "$(terraform output -raw bastion_public_ip)" \
#       --scheduler-ip "$(terraform output -raw scheduler_private_ip)"
#
# What it does:
#   1. Creates a tarball of the scaler source (excluding .git, __pycache__, etc.)
#   2. Uploads to the bastion, then forwards to the scheduler (two-hop SCP)
#   3. Extracts, creates a Python 3.11 venv, installs with pip
#   4. Restarts the scaler-scheduler systemd service
##############################################################################
set -euo pipefail

SCALER_SRC=""
BASTION_IP=""
SCHEDULER_IP=""
SSH_KEY="${SSH_KEY:-$HOME/.ssh/scaler_scheduler}"
SSH_USER="opc"

usage() {
    echo "Usage: $0 --scaler-src <path> --bastion-ip <ip> --scheduler-ip <ip>"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scaler-src)    SCALER_SRC="$2";    shift 2 ;;
        --bastion-ip)    BASTION_IP="$2";    shift 2 ;;
        --scheduler-ip)  SCHEDULER_IP="$2";  shift 2 ;;
        --ssh-key)       SSH_KEY="$2";       shift 2 ;;
        -h|--help)       usage ;;
        *)               echo "Unknown argument: $1"; usage ;;
    esac
done

if [[ -z "$SCALER_SRC" || -z "$BASTION_IP" || -z "$SCHEDULER_IP" ]]; then
    echo "ERROR: --scaler-src, --bastion-ip, and --scheduler-ip are required."
    usage
fi

SCALER_SRC="$(cd "$SCALER_SRC" && pwd)"
if [[ ! -f "$SCALER_SRC/pyproject.toml" ]]; then
    echo "ERROR: $SCALER_SRC does not look like the scaler source (missing pyproject.toml)."
    exit 1
fi

SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

ssh_bastion() {
    ssh $SSH_OPTS "${SSH_USER}@${BASTION_IP}" "$@"
}

ssh_scheduler() {
    ssh $SSH_OPTS -o "ProxyCommand=ssh $SSH_OPTS -W %h:%p ${SSH_USER}@${BASTION_IP}" "${SSH_USER}@${SCHEDULER_IP}" "$@"
}

TARBALL="/tmp/scaler-deploy-$$.tar.gz"
REMOTE_TARBALL="/tmp/scaler-source.tar.gz"

# ---------------------------------------------------------------------------
# Step 1: Create tarball
# ---------------------------------------------------------------------------
echo "=== Creating source tarball ==="
tar -czf "$TARBALL" \
    -C "$SCALER_SRC" \
    --exclude='.git' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='.eggs' \
    --exclude='*.egg-info' \
    --exclude='build' \
    --exclude='dist' \
    --exclude='.tox' \
    --exclude='.venv' \
    --exclude='.devcontainer' \
    .
echo "  Tarball: $TARBALL ($(du -h "$TARBALL" | cut -f1))"

# ---------------------------------------------------------------------------
# Step 2: Upload via bastion (two-hop: local → bastion → scheduler)
# ---------------------------------------------------------------------------
echo "=== Uploading to scheduler ($SCHEDULER_IP via bastion $BASTION_IP) ==="
scp $SSH_OPTS -o "ProxyCommand=ssh $SSH_OPTS -W %h:%p ${SSH_USER}@${BASTION_IP}" \
    "$TARBALL" "${SSH_USER}@${SCHEDULER_IP}:${REMOTE_TARBALL}"

rm -f "$TARBALL"

# ---------------------------------------------------------------------------
# Step 3: Extract, create venv, install
# ---------------------------------------------------------------------------
echo "=== Installing on scheduler ==="
ssh_scheduler bash -s <<'REMOTE_SCRIPT'
set -euo pipefail

echo "Extracting source..."
sudo mkdir -p /opt/scaler/src
sudo chown -R opc:opc /opt/scaler
cd /opt/scaler/src
rm -rf ./*
tar -xzf /tmp/scaler-source.tar.gz
rm -f /tmp/scaler-source.tar.gz

echo "Creating virtualenv..."
cd /opt/scaler
if [[ ! -d venv ]]; then
    python3.11 -m venv venv
fi
source venv/bin/activate

# Enable GCC 14 for C++20 support (std::format)
if [[ -f /opt/rh/gcc-toolset-14/enable ]]; then
    source /opt/rh/gcc-toolset-14/enable
fi
export CC=gcc CXX=g++ CMAKE_PREFIX_PATH=/usr/local

echo "Upgrading pip..."
pip install --upgrade pip 2>&1 | tail -1

echo "Installing scaler from local source..."
cd /opt/scaler/src
pip install -e "." 2>&1 | tail -10

echo "Pinning configargparse compatibility..."
pip install 'configargparse>=1.7,<1.7.5' 2>&1 | tail -1

echo "Installing OCI SDK..."
pip install oci cloudpickle 2>&1 | tail -1

echo "Verifying scaler_scheduler is available..."
which scaler_scheduler
which scaler_worker_manager_oci_raw_container_instance

echo "Restarting scaler services..."
sudo systemctl daemon-reload
sudo systemctl restart scaler-scheduler
sleep 3
sudo systemctl status scaler-scheduler --no-pager | head -10

echo ""
echo "Restarting scaler-worker-manager service..."
sudo systemctl restart scaler-worker-manager || echo "  (worker manager service not configured — skip)"
sleep 2
sudo systemctl status scaler-worker-manager --no-pager | head -10 || true
REMOTE_SCRIPT

echo ""
echo "=== Deploy complete ==="
echo ""
echo "Check logs:"
echo "  ssh to scheduler: 'sudo journalctl -u scaler-scheduler -f'"
echo "  ssh to scheduler: 'sudo journalctl -u scaler-worker-manager -f'"
