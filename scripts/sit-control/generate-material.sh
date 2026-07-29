#!/usr/bin/env bash
set -euo pipefail

target="${1:?usage: $0 <target-directory>}"
root_dir="$(git rev-parse --show-toplevel)"
mkdir -p "${target}/ca" "${target}/providers" "${target}/endpoints"
chmod 700 "${target}" "${target}/ca" "${target}/providers" "${target}/endpoints"
umask 077

openssl req -x509 -newkey rsa:3072 -sha256 -nodes \
  -keyout "${target}/ca/ca-key.pem" \
  -out "${target}/ca/ca.pem" \
  -days 2 \
  -subj "/CN=Mercury bounded SIT CA"

openssl req -newkey rsa:2048 -sha256 -nodes \
  -keyout "${target}/ca/tls-key.pem" \
  -out "${target}/ca/tls.csr" \
  -subj "/CN=mercury.test"

openssl x509 -req -sha256 \
  -in "${target}/ca/tls.csr" \
  -CA "${target}/ca/ca.pem" \
  -CAkey "${target}/ca/ca-key.pem" \
  -CAcreateserial \
  -out "${target}/ca/tls.pem" \
  -days 2 \
  -extfile <(printf '%s\n' \
    'subjectAltName=DNS:mercury.test,DNS:mercury-tls,DNS:localhost,IP:127.0.0.1' \
    'extendedKeyUsage=serverAuth')

openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -sha256 -nodes \
  -keyout "${target}/ca/apple-root-key.pem" \
  -out "${target}/ca/apple-root.pem" \
  -days 2 \
  -subj "/CN=Mercury SIT Apple Root" \
  -addext 'basicConstraints=critical,CA:TRUE' \
  -addext 'keyUsage=critical,keyCertSign,cRLSign'

openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -sha256 -nodes \
  -keyout "${target}/ca/apple-leaf-key.pem" \
  -out "${target}/ca/apple-leaf.csr" \
  -subj "/CN=Mercury SIT Apple Leaf"

openssl x509 -req -sha256 \
  -in "${target}/ca/apple-leaf.csr" \
  -CA "${target}/ca/apple-root.pem" \
  -CAkey "${target}/ca/apple-root-key.pem" \
  -CAcreateserial \
  -out "${target}/ca/apple-leaf.pem" \
  -days 2 \
  -extfile <(printf '%s\n' \
    'basicConstraints=critical,CA:FALSE' \
    'keyUsage=critical,digitalSignature')

cd "${root_dir}"
bun scripts/sit-control/write-material.ts "${target}"
echo "✅ Generated bounded SIT trust and secret material in ${target}"
