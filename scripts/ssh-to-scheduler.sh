#!/usr/bin/env bash
##############################################################################
# SSH to the scheduler instance through the bastion.
#
# Usage:
#   ./scripts/ssh-to-scheduler.sh              # interactive shell
#   ./scripts/ssh-to-scheduler.sh hostname      # run a command
#   SSH_KEY=~/.ssh/mykey ./scripts/ssh-to-scheduler.sh  # custom key
#
# Reads connection details from Terraform outputs automatically.
##############################################################################
set -euo pipefail

SSH_KEY="${SSH_KEY:-$(terraform output -raw ssh_private_key_path 2>/dev/null || echo ~/.ssh/id_ed25519)}"
BASTION_IP="$(terraform output -raw bastion_public_ip 2>/dev/null)" || {
  echo "ERROR: Could not read bastion_public_ip. Is the bastion provisioned?" >&2
  exit 1
}
SCHEDULER_IP="$(terraform output -raw scheduler_private_ip 2>/dev/null)" || {
  echo "ERROR: Could not read scheduler_private_ip. Is the scheduler provisioned?" >&2
  exit 1
}

exec ssh -i "$SSH_KEY" \
  -o StrictHostKeyChecking=accept-new \
  -o "ProxyCommand=ssh -i $SSH_KEY -o StrictHostKeyChecking=accept-new -W %h:%p opc@$BASTION_IP" \
  opc@"$SCHEDULER_IP" "$@"
