#!/usr/bin/env bash
set -e

ROOT="$(dirname "$(dirname "$0")")"
WORKDIR="$(mktemp -d || exit 1)"
trap 'rm -rf ${WORKDIR}' EXIT

# shellcheck source=tests/helpers.sh
. "${ROOT}/tests/helpers.sh"

export PACKAGE_ROOT="${ROOT}/package"
export TAILSCALE_ROOT="${WORKDIR}"
export TAILSCALED_SOCK="${WORKDIR}/tailscaled.sock"

export PATH="${WORKDIR}:/usr/bin:/bin:/usr/sbin:/sbin"
mock "${WORKDIR}/ubnt-device-info" "2.0.0"
mock "${WORKDIR}/systemctl" "" 1

assert_eq "$("${ROOT}/package/manage.sh" status)" "Tailscale is not installed" "Tailscaled should be reported as not installed"

mock "${WORKDIR}/tailscale" "0.0.0"

mock "${WORKDIR}/systemctl" "" 1
assert_eq "$("${ROOT}/package/manage.sh" status)" "Tailscaled is not running" "Tailscaled should be reported as not running"

mock "${WORKDIR}/systemctl" "" 0
assert_eq "$("${ROOT}/package/manage.sh" status)" "Tailscaled is running
0.0.0" "Tailscaled should be reported as running with the version number"

# ── device advisories ─────────────────────────────────────────────────────────
# Advisories are printed to stderr by `status` for hardware with a known issue,
# pointing at the matching README troubleshooting entry.  Cases are
# model|tailscale-env contents|expected substring (empty => no advisory).
mock "${WORKDIR}/systemctl" "" 0
advisory_cases=(
    "UniFi Cloud Gateway Max||slow-tcp-throughput-on-cloud-gateway-devices"
    "UniFi Cloud Gateway Max|TS_TUN_DISABLE_TCP_GRO=1|"
    "UniFi Cloud Gateway Max|TAILSCALED_FLAGS=\"--tun userspace-networking\"|"
    "UniFi Cloud Gateway Max|TAILSCALE_ADVISORIES=\"false\"|"
    "UniFi Dream Machine Pro||"
    "UniFi Network Video Recorder Pro||userspace-networking-on-nvr-and-nas-devices"
    "UNASPRO||userspace-networking-on-nvr-and-nas-devices"
)
for advisory_case in "${advisory_cases[@]}"; do
    IFS='|' read -r model env_line expected <<< "$advisory_case"
    printf '%s\n' "$env_line" > "${WORKDIR}/tailscale-env"
    status_out=$(TAILSCALE_DEVICE_MODEL="$model" "${ROOT}/package/manage.sh" status 2>&1)
    if [ -n "$expected" ]; then
        assert_contains "$status_out" "NOTICE:" "status prints an advisory for '$model' with env '$env_line'"
        assert_contains "$status_out" "$expected" "advisory for '$model' links the README entry '$expected'"
    else
        assert_not_contains "$status_out" "NOTICE:" "status prints no advisory for '$model' with env '$env_line'"
    fi
done

# Without an override the model comes from ubnt-device-info; the default mock
# returns a version string that matches no advisory.
assert_not_contains "$("${ROOT}/package/manage.sh" status 2>&1)" "NOTICE:" "status prints no advisory for an unrecognised ubnt-device-info model"
