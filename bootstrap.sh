#!/usr/bin/env bash
# Automates the AWS Client VPN "Enable mutual authentication" steps (Linux/macOS).
# Source: https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/client-auth-mutual-enable.html
set -euo pipefail

rm setup-certs.sh
# Create a file with the content of the clipboard and save it as setup-certs.sh
cp setup-template.sh setup-certs.sh
chmod +x setup-certs.sh
./setup-certs.sh