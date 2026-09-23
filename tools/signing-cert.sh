#!/bin/bash
# Make the household's own code-signing certificate, once, on the Mac that builds.
#
# Why: macOS remembers privacy grants (the Accessibility switch the Undertale row needs)
# by the app's signature. An ad-hoc signature is different on every build, so after an
# update the switch looks on and does nothing. A self-signed certificate gives every
# build the same identity, and build.sh signs with it when it is in the keychain.
#
# Usage: tools/signing-cert.sh          creates "Xenon Doctor" in the login keychain
#        tools/signing-cert.sh --show   prints whether it is there
#
# The trust step may show one macOS password dialog; that is the keychain asking, once.
set -euo pipefail
NAME="Xenon Doctor"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if [[ "${1:-}" == "--show" ]]; then
    security find-identity -v -p codesigning | grep "\"${NAME}\"" || echo "no '${NAME}' certificate"
    exit 0
fi

if security find-identity -v -p codesigning | grep -q "\"${NAME}\""; then
    echo "'${NAME}' is already in the keychain"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=${NAME}/O=Xenon Doctor" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false" >/dev/null 2>&1
# macOS's keychain cannot read the AES/SHA-256 bundle OpenSSL 3 writes by default.
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -out "$WORK/id.p12" -passout pass:xenon \
    -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES >/dev/null 2>&1
# -A: any program may use the key without a keychain dialog. codesign otherwise stalls on
# one at every build (seen 2026-09-24 even with -T /usr/bin/codesign).
security import "$WORK/id.p12" -k "$KEYCHAIN" -P xenon -A >/dev/null
# Mark it trusted for code signing, else the keychain lists it as invalid.
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"
security find-identity -v -p codesigning | grep "\"${NAME}\"" && echo "'${NAME}' ready; build.sh will use it"
