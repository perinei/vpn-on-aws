#!/usr/bin/env bash
# Deletes everything created by setup-certs.sh:
#   - ACM certificates (server and client), read from acm-arns.env
#   - SSM parameters /vpn/server-cert and /vpn/client-cert
#   - Local easy-rsa work directory and custom folder (keys and certs)
# ACM certificates still attached to a Client VPN endpoint cannot be deleted;
# those are reported and skipped.
set -euo pipefail

# ---- Configuration (must match setup-certs.sh) ----
AWS_REGION="${AWS_REGION:-us-east-1}"
WORK_DIR="${WORK_DIR:-$HOME/easy-rsa-work}"
CUSTOM_DIR="${CUSTOM_DIR:-$HOME/custom_folder}"
ARNS_FILE="$CUSTOM_DIR/acm-arns.env"

# ---- Preflight checks ----
for cmd in aws; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: '$cmd' is required but not installed." >&2; exit 1; }
done
aws sts get-caller-identity >/dev/null || { echo "ERROR: AWS credentials are not configured." >&2; exit 1; }

# ---- Confirmation ----
echo "This will permanently delete:"
echo "  - ACM certificates listed in $ARNS_FILE (region $AWS_REGION)"
echo "  - SSM parameters /vpn/server-cert and /vpn/client-cert (region $AWS_REGION)"
echo "  - $WORK_DIR"
echo "  - $CUSTOM_DIR"
read -r -p "Type 'yes' to continue: " answer
[ "$answer" = "yes" ] || { echo "Aborted."; exit 0; }

# ---- Step 1: ACM certificates ----
if [ -f "$ARNS_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ARNS_FILE"
  for arn in "${SERVER_CERT_ARN:-}" "${CLIENT_CERT_ARN:-}"; do
    [ -n "$arn" ] || continue
    if aws acm delete-certificate --region "$AWS_REGION" --certificate-arn "$arn" 2>/dev/null; then
      echo "Deleted ACM certificate: $arn"
    else
      echo "WARNING: could not delete ACM certificate (already gone, or still in use by a Client VPN endpoint): $arn" >&2
    fi
  done
else
  echo "WARNING: $ARNS_FILE not found; skipping ACM certificate deletion." >&2
fi

# ---- Step 2: SSM parameters ----
for name in /vpn/server-cert /vpn/client-cert; do
  if aws ssm delete-parameter --region "$AWS_REGION" --name "$name" 2>/dev/null; then
    echo "Deleted SSM parameter: $name"
  else
    echo "WARNING: SSM parameter not found or not deleted: $name" >&2
  fi
done

# ---- Step 3: Local files ----
rm -rf "$WORK_DIR"
echo "Removed: $WORK_DIR"
rm -rf "$CUSTOM_DIR"
echo "Removed: $CUSTOM_DIR"

echo "Cleanup complete."
