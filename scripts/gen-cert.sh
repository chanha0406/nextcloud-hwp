#!/usr/bin/env bash
# Generate RSA key + CSR for Nextcloud App Store code signing (app id: hwpdocuments).
# Keep the .key private. Submit the .csr via PR to:
#   https://github.com/nextcloud/app-certificate-requests
set -euo pipefail

APP_ID="hwpdocuments"
CERT_DIR="${CERT_DIR:-$HOME/.nextcloud/certificates}"
KEY="$CERT_DIR/${APP_ID}.key"
CSR="$CERT_DIR/${APP_ID}.csr"

mkdir -p "$CERT_DIR"
chmod 700 "$CERT_DIR"

if [[ -f "$KEY" ]]; then
	echo "Refusing to overwrite existing key: $KEY" >&2
	echo "Set CERT_DIR=... or remove/rename the key first." >&2
	exit 1
fi

openssl req -nodes -newkey rsa:4096 \
	-keyout "$KEY" \
	-out "$CSR" \
	-subj "/CN=${APP_ID}"

chmod 600 "$KEY"
echo
echo "Created:"
echo "  private key: $KEY   (NEVER commit / share)"
echo "  CSR:         $CSR"
echo
echo "Next steps:"
echo "  1. Open a PR at https://github.com/nextcloud/app-certificate-requests"
echo "     with $CSR and a link to https://github.com/chanha0406/nextcloud-hwp"
echo "  2. Save the signed .crt they return as:"
echo "       $CERT_DIR/${APP_ID}.crt"
echo "  3. Run: npm run release"
