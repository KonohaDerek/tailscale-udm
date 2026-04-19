#!/bin/bash

ROOT="$(dirname "$(dirname "$0")")"
WORKDIR="$(mktemp -d || exit 1)"
trap 'rm -rf ${WORKDIR}' EXIT

# shellcheck source=tests/helpers.sh
. "${ROOT}/tests/helpers.sh"

export PATH="${WORKDIR}:${PATH}"
export TAILSCALE_ROOT="${WORKDIR}"
export SQL_CAPTURE_PATH="${WORKDIR}/captured.sql"

cat > "$WORKDIR/openssl" <<'EOF'
#!/usr/bin/env bash

if [ "$1" != "x509" ]; then
    echo "Unexpected openssl command: $*" >&2
    exit 1
fi

shift

case "$1" in
    -noout)
        shift
        case "$1" in
            -startdate)
                echo "notBefore=Jul 29 09:27:20 2025 GMT"
                ;;
            -enddate)
                echo "notAfter=Oct 27 09:27:19 2025 GMT"
                ;;
            -subject)
                echo "subject=CN = wandi-gateway.taildb452.ts.net"
                ;;
            -issuer)
                echo "issuer=CN = E5"
                ;;
            -serial)
                echo "serial=1234ABCD"
                ;;
            -fingerprint)
                echo "sha256 Fingerprint=AA:BB:CC:DD"
                ;;
            *)
                echo "Unexpected openssl -noout arguments: $*" >&2
                exit 1
                ;;
        esac
        ;;
    -text)
        echo "        Version: 3 (0x2)"
        ;;
    *)
        echo "Unexpected openssl arguments: $*" >&2
        exit 1
        ;;
esac
EOF
chmod +x "$WORKDIR/openssl"

cat > "$WORKDIR/psql" <<'EOF'
#!/usr/bin/env bash
cat > "$SQL_CAPTURE_PATH"
EOF
chmod +x "$WORKDIR/psql"

cat > "$WORKDIR/sudo" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-u" ]; then
    shift 2
fi
exec "$@"
EOF
chmod +x "$WORKDIR/sudo"

cat > "$WORKDIR/test.crt" <<'EOF'
-----BEGIN CERTIFICATE-----
MOCK CERTIFICATE
-----END CERTIFICATE-----
EOF

cat > "$WORKDIR/test.key" <<'EOF'
-----BEGIN PRIVATE KEY-----
MOCK PRIVATE KEY
-----END PRIVATE KEY-----
EOF

output=$("${ROOT}/package/helpers/cert-db-register.sh" \
    "12345678-1234-1234-1234-123456789012" \
    "$WORKDIR/test.crt" \
    "$WORKDIR/test.key" \
    "wandi-gateway.taildb452.ts.net" 2>&1)

assert_contains "$output" "Certificate registered in database with UUID: 12345678-1234-1234-1234-123456789012" "Helper reports successful registration"

captured_sql=$(cat "$SQL_CAPTURE_PATH")
assert_contains "$captured_sql" "INSERT INTO user_certificates" "Generated SQL inserts into user_certificates"
assert_contains "$captured_sql" "12345678-1234-1234-1234-123456789012" "Generated SQL includes the certificate UUID"
assert_contains "$captured_sql" "Tailscale Certificate - wandi-gateway.taildb452.ts.net" "Generated SQL includes the certificate name"
assert_contains "$captured_sql" '"CN":"wandi-gateway.taildb452.ts.net"' "Generated SQL includes the subject CN"
assert_contains "$captured_sql" '"CN":"E5"' "Generated SQL includes the issuer CN"
assert_contains "$captured_sql" "AABBCCDD" "Generated SQL normalizes the SHA256 fingerprint"
assert_contains "$captured_sql" "MOCK CERTIFICATE" "Generated SQL includes the certificate body"
assert_contains "$captured_sql" "MOCK PRIVATE KEY" "Generated SQL includes the private key body"

echo "All certificate database tests passed!"
