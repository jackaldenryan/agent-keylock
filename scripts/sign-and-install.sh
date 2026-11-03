#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
identity="API Key Lock Signing"
support="${HOME}/Library/Application Support/APIKeyLock/signing"
p12="$support/APIKeyLockSigning.p12"
pass_file="$support/p12-password"
keychain_name="api-key-lock-signing"
keychain_pass_file="$support/keychain-password"
install_dir="${HOME}/.local/libexec/api-key-lock"
binary="$install_dir/keylock"

mkdir -p "$support" "$install_dir"
chmod 700 "$support"

if [[ ! -f "$pass_file" ]]; then
  /usr/bin/openssl rand -base64 24 > "$pass_file"
  chmod 600 "$pass_file"
fi
if [[ ! -f "$keychain_pass_file" ]]; then
  /usr/bin/openssl rand -base64 24 > "$keychain_pass_file"
  chmod 600 "$keychain_pass_file"
fi

p12_pass="$(tr -d '[:space:]' < "$pass_file")"
keychain_pass="$(tr -d '[:space:]' < "$keychain_pass_file")"

if [[ ! -f "$p12" ]]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  cat > "$tmp/openssl.cnf" <<'EOF'
[req]
distinguished_name = req_distinguished_name
prompt = no
x509_extensions = ext

[req_distinguished_name]
CN = API Key Lock Signing
O = API Key Lock

[ext]
basicConstraints = critical, CA:TRUE
keyUsage = critical, digitalSignature, keyCertSign
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF
  /usr/bin/openssl req -new -x509 -days 3650 -nodes \
    -config "$tmp/openssl.cnf" \
    -keyout "$tmp/key.pem" \
    -out "$tmp/cert.pem"
  /usr/bin/openssl pkcs12 -export \
    -inkey "$tmp/key.pem" \
    -in "$tmp/cert.pem" \
    -out "$p12" \
    -passout "pass:$p12_pass" \
    -name "$identity"
  chmod 600 "$p12"
  rm -rf "$tmp"
  trap - EXIT
fi

previous=()
while IFS= read -r line; do
  path="${line//\"/}"
  path="${path#"${path%%[![:space:]]*}"}"
  path="${path%"${path##*[![:space:]]}"}"
  [[ -n "$path" && -e "$path" ]] || continue
  previous+=("$path")
done < <(/usr/bin/security list-keychains -d user)
if [[ ${#previous[@]} -eq 0 ]]; then
  echo "refusing to replace an empty keychain search list" >&2
  exit 1
fi

cleanup() {
  /usr/bin/security lock-keychain "$keychain_name" >/dev/null 2>&1 || true
  if [[ ${#previous[@]} -gt 0 ]]; then
    /usr/bin/security list-keychains -d user -s "${previous[@]}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

keychain_path="${HOME}/Library/Keychains/${keychain_name}-db"
if [[ ! -e "$keychain_path" && ! -e "${HOME}/Library/Keychains/${keychain_name}.keychain-db" ]]; then
  /usr/bin/security create-keychain -p "$keychain_pass" "$keychain_name"
fi
if [[ -e "${HOME}/Library/Keychains/${keychain_name}.keychain-db" ]]; then
  keychain_path="${HOME}/Library/Keychains/${keychain_name}.keychain-db"
fi

/usr/bin/security unlock-keychain -p "$keychain_pass" "$keychain_name"
search=("$keychain_path")
for path in "${previous[@]}"; do
  [[ "$path" == "$keychain_path" ]] && continue
  search+=("$path")
done
/usr/bin/security list-keychains -d user -s "${search[@]}"
if ! /usr/bin/security find-identity -v -p codesigning "$keychain_path" 2>/dev/null | grep -F "$identity" >/dev/null; then
  /usr/bin/security import "$p12" -k "$keychain_path" -P "$p12_pass" -T /usr/bin/codesign -T /usr/bin/security
fi
/usr/bin/security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_pass" "$keychain_name" >/dev/null

cd "$root"
swift build -c release --product keylock
cp -f .build/release/keylock "$binary"
chmod 755 "$binary"
/usr/bin/codesign --force --sign "$identity" --keychain "$keychain_name" \
  --options runtime \
  --identifier com.apikeylock.keylock \
  "$binary"
echo "installed $binary"
echo "certificate: $identity"
echo "signing secrets are in $support"
echo "signing keychain is $keychain_path"
echo "Move both off this Mac before treating the signature as a boundary against an agent."
