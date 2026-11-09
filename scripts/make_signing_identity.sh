#!/usr/bin/env bash
# Creates the project's self-signed release certificate and stores it only as
# GitHub Actions secrets (MACOS_SIGNING_P12, MACOS_SIGNING_P12_PASSWORD).
# No copy stays on disk. Run once by the maintainer; see docs/RELEASING.md.
set -euo pipefail

if gh secret list | grep -q '^MACOS_SIGNING_P12[[:space:]]' && [[ "${1:-}" != "--replace" ]]; then
    echo "MACOS_SIGNING_P12 exists already. Replacing it changes the signature: users re-grant permissions once."
    echo "Run with --replace to continue."
    exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
password="$(openssl rand -hex 24)"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout "$work/key.pem" -out "$work/cert.pem" \
    -subj "/CN=macprompter Release Signing" \
    -addext "basicConstraints=critical,CA:false" -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" -name "macprompter Release Signing" \
    -out "$work/signing.p12" -passout pass:"$password" -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
base64 -i "$work/signing.p12" | gh secret set MACOS_SIGNING_P12
printf '%s' "$password" | gh secret set MACOS_SIGNING_P12_PASSWORD
openssl x509 -in "$work/cert.pem" -noout -subject -enddate -fingerprint -sha256
echo "Stored as GitHub secrets MACOS_SIGNING_P12 and MACOS_SIGNING_P12_PASSWORD."
