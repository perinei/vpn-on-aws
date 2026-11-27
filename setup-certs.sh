#!/usr/bin/env bash
# Automates the AWS Client VPN "Enable mutual authentication" steps (Linux/macOS).
# Source: https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/client-auth-mutual-enable.html
set -euo pipefail

# ---- Configuration (override with environment variables) ----
AWS_REGION="${AWS_REGION:-us-east-1}"          # Must match the region where you'll create the Client VPN endpoint
CLIENT_NAME="${CLIENT_NAME:-clientVPN.domain.tld}"
SERVER_NAME="${SERVER_NAME:-serverVPN.domain.tld}"
CA_CN="${CA_CN:-Client VPN CA}"
WORK_DIR="${WORK_DIR:-$HOME/easy-rsa-work}"
CUSTOM_DIR="${CUSTOM_DIR:-$HOME/custom_folder}"

# ---- Preflight checks ----
for cmd in git aws; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: '$cmd' is required but not installed." >&2; exit 1; }
done
aws sts get-caller-identity >/dev/null || { echo "ERROR: AWS credentials are not configured." >&2; exit 1; }

# Run easy-rsa non-interactively
export EASYRSA_BATCH=1

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Step 1: Clone easy-rsa
if [ ! -d easy-rsa ]; then
  git clone https://github.com/OpenVPN/easy-rsa.git
fi
cd easy-rsa/easyrsa3

# Step 2: Initialize PKI (remove any existing PKI so the script is repeatable)
rm -rf pki
./easyrsa init-pki

# Step 3: Build the CA (nopass, no prompts)
EASYRSA_REQ_CN="$CA_CN" ./easyrsa build-ca nopass

# Step 4: Server certificate and key
EASYRSA_REQ_CN="$SERVER_NAME" ./easyrsa --san=DNS:"$SERVER_NAME" build-server-full "$SERVER_NAME" nopass

# Step 5: Client certificate and key
EASYRSA_REQ_CN="$CLIENT_NAME" ./easyrsa build-client-full "$CLIENT_NAME" nopass

# Step 6: Copy certificates and keys to a custom folder
mkdir -p "$CUSTOM_DIR"
cp pki/ca.crt "$CUSTOM_DIR/"
cp pki/issued/"$SERVER_NAME".crt "$CUSTOM_DIR/"
cp pki/private/"$SERVER_NAME".key "$CUSTOM_DIR/"
cp pki/issued/"$CLIENT_NAME".crt "$CUSTOM_DIR/"
cp pki/private/"$CLIENT_NAME".key "$CUSTOM_DIR/"
cd "$CUSTOM_DIR"

# Step 7: Import server and client certificates into ACM in the target region
# ACM has no friendly-name field, so the name is stored as the "Name" tag
# (shown as the Name column in the ACM console).
SERVER_ARN=$(aws acm import-certificate \
  --region "$AWS_REGION" \
  --certificate fileb://"$SERVER_NAME".crt \
  --private-key fileb://"$SERVER_NAME".key \
  --certificate-chain fileb://ca.crt \
  --tags Key=Name,Value=client-vpn-server-"$SERVER_NAME" \
  --query CertificateArn --output text)

CLIENT_ARN=$(aws acm import-certificate \
  --region "$AWS_REGION" \
  --certificate fileb://"$CLIENT_NAME".crt \
  --private-key fileb://"$CLIENT_NAME".key \
  --certificate-chain fileb://ca.crt \
  --tags Key=Name,Value=client-vpn-client-"$CLIENT_NAME" \
  --query CertificateArn --output text)

# Store the ARNs in SSM Parameter Store (--overwrite so the script can be rerun)
aws ssm put-parameter \
  --region "$AWS_REGION" \
  --name /vpn/server-cert \
  --type String \
  --value "$SERVER_ARN" \
  --overwrite >/dev/null

aws ssm put-parameter \
  --region "$AWS_REGION" \
  --name /vpn/client-cert \
  --type String \
  --value "$CLIENT_ARN" \
  --overwrite >/dev/null

# Save the ARNs for the endpoint creation step
cat > "$CUSTOM_DIR/acm-arns.env" <<EOF
SERVER_CERT_ARN=$SERVER_ARN
CLIENT_CERT_ARN=$CLIENT_ARN
AWS_REGION=$AWS_REGION
EOF

echo "Done."
echo "Server certificate ARN: $SERVER_ARN"
echo "Client certificate ARN: $CLIENT_ARN"
echo "Saved to: $CUSTOM_DIR/acm-arns.env"
echo "Use the server ARN as the server certificate and, for mutual authentication, the client ARN as the client root certificate when you create the Client VPN endpoint."