#!/usr/bin/env bash
# Creates the project's self-signed signing certificate "macprompter Release Signing".
# Run once by the maintainer (docs/RELEASING.md). It is stored
#   - as GitHub Actions secrets MACOS_SIGNING_P12 and MACOS_SIGNING_P12_PASSWORD (releases), and
#   - in the login keychain, trusted for code signing (local builds via scripts/install.sh),
# so test builds and releases share one signature and macOS keeps privacy grants when
# switching between them. No file copy stays on disk. macOS asks for your password
# once to trust the certificate.
#   scripts/make_signing_identity.sh             first setup
#   scripts/make_signing_identity.sh --replace   new certificate (users re-grant permissions once)
set -euo pipefail

name="macprompter Release Signing"
repo="$(git remote get-url origin | sed -E 's#^(https://github.com/|git@github.com:)##; s#\.git$##')"
keychain="$HOME/Library/Keychains/login.keychain-db"

if [[ "${1:-}" != "--replace" ]] && { gh secret list --repo "$repo" | grep -q '^MACOS_SIGNING_P12[[:space:]]' || security find-certificate -c "$name" "$keychain" >/dev/null 2>&1; }; then
    echo "A signing certificate exists already (GitHub secret or keychain)."
    echo "Replacing it changes the signature: users re-grant permissions once. Run with --replace to continue."
    exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
password="$(openssl rand -hex 24)"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout "$work/key.pem" -out "$work/cert.pem" \
    -subj "/CN=$name" \
    -addext "basicConstraints=critical,CA:false" -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
# 3DES/SHA-1 container: macOS `security import` rejects the OpenSSL 3 default format.
openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" -name "$name" \
    -out "$work/signing.p12" -passout pass:"$password" -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1

# Remove an older identity of the same name so codesign finds exactly one.
while hash="$(security find-certificate -c "$name" -Z "$keychain" 2>/dev/null | awk '/^SHA-1/ { print $3; exit }')" && [[ -n "$hash" ]]; do
    security delete-identity -Z "$hash" "$keychain" >/dev/null 2>&1 || security delete-certificate -Z "$hash" "$keychain" >/dev/null
done
security import "$work/signing.p12" -k "$keychain" -P "$password" -T /usr/bin/codesign >/dev/null
echo "Trusting the certificate for code signing (macOS asks for your password) …"
security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$work/cert.pem"

base64 -i "$work/signing.p12" | gh secret set MACOS_SIGNING_P12 --repo "$repo"
printf '%s' "$password" | gh secret set MACOS_SIGNING_P12_PASSWORD --repo "$repo"

openssl x509 -in "$work/cert.pem" -noout -subject -enddate -fingerprint -sha256
security find-identity -v -p codesigning | grep "$name"
echo "Stored in the login keychain and as GitHub secrets for $repo."
