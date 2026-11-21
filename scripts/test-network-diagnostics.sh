#!/usr/bin/env bash

# Replay portal failures without changing Wi-Fi, needing root, or making requests.
set -eu

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_dir="$(mktemp -d)"
trap 'rm -rf -- "$fixture_dir"' EXIT

cat > "$fixture_dir/fixture" <<'STUB'
#!/usr/bin/env bash
set -eu
case "${0##*/}" in
  curl)
    printf '%s\n' "$*" >> "$NETWORK_TEST_LOG"
    if [[ "$1" != -q || "$*" != *"--noproxy *"* ]]; then
      printf 'Portal requests must bypass curlrc and proxies.\n' >&2
      exit 99
    fi
    if [[ "${*: -1}" == http://connectivitycheck.gstatic.com/generate_204 ]]; then
      case "$NETWORK_TEST_CASE" in
        clear) printf '\n204|' ;;
        inline) printf '\n200|' ;;
        probe-failure)
          printf 'curl: (28) HTTP probe timed out\n\n000|'
          exit 28
          ;;
        *) printf '\n302|https://login.example.test/' ;;
      esac
    else
      case "$NETWORK_TEST_CASE" in
        reachable|private-portal) printf '\n200|https://login.example.test/' ;;
        tls)
          printf 'curl: (60) Certificate verification failed\n\n000|https://login.example.test/'
          exit 60
          ;;
        dns)
          printf 'curl: (6) Could not resolve host\n\n000|https://login.example.test/'
          exit 6
          ;;
        redirect-chain)
          printf 'curl: (28) Connection timed out\n\n000|https://final.example.test/login'
          exit 28
          ;;
        *)
          printf 'curl: (28) Connection timed out\n\n000|https://login.example.test/'
          exit 28
          ;;
      esac
    fi
    ;;
  getent)
    printf '%s\n' "$*" >> "$NETWORK_TEST_LOG"
    case "$NETWORK_TEST_CASE" in
      dns) exit 2 ;;
      private-portal) address=192.168.10.1 ;;
      lower-boundary) address=100.63.255.254 ;;
      upper-boundary) address=100.128.0.1 ;;
      last-cgnat) address=100.127.255.254 ;;
      *) address=100.64.1.2 ;;
    esac
    printf '%s STREAM %s\n%s DGRAM %s\n' "$address" "$2" "$address" "$2"
    ;;
  ip)
    case "$*" in
      'link show tailscale0') [[ "$NETWORK_TEST_CASE" != no-tailscale ]] ;;
      '-4 route get '*) printf '%s via 172.18.0.2 dev wlp2s0 src 172.18.128.134\n' "$4" ;;
      '-4 route show default') printf 'default via 172.18.0.2 dev wlp2s0\n' ;;
      '-brief address') printf 'wlp2s0 UP 172.18.128.134/16\n' ;;
    esac
    ;;
  busctl) printf 'b false\n' ;;
  nmcli)
    if [[ "$*" == '-t -f DEVICE,TYPE device status' ]]; then
      printf 'wlp2s0:wifi\n'
    else
      printf 'GENERAL.CONNECTION: Test Wi-Fi\nIP4.DNS: 172.18.0.2\n'
    fi
    ;;
esac
STUB
chmod +x "$fixture_dir/fixture"
for tool in curl getent ip busctl nmcli; do
  ln -s fixture "$fixture_dir/$tool"
done

export PATH="$fixture_dir:$PATH"
export NETWORK_TEST_LOG="$fixture_dir/calls"
output="$fixture_dir/output"
cases=0

run_case() {
  local scenario="$1" expected_status="$2" status=0
  shift 2
  : > "$NETWORK_TEST_LOG"
  NETWORK_TEST_CASE="$scenario" bash "$repo_dir/dotfiles/bash/network-diagnostics.sh" "$@" > "$output" 2>&1 || status=$?
  if ((status != expected_status)); then
    cat "$output"
    printf 'FAIL: %s: expected exit %s, got %s\n' "$scenario" "$expected_status" "$status" >&2
    exit 1
  fi
  cases=$((cases + 1))
}

contains() {
  if ! grep -Fq -- "$1" "$output"; then
    cat "$output"
    printf 'FAIL: missing output: %s\n' "$1" >&2
    exit 1
  fi
}

absent() {
  if grep -Fq -- "$1" "$output"; then
    cat "$output"
    printf 'FAIL: unexpected output: %s\n' "$1" >&2
    exit 1
  fi
}

# The original failure: HTTP redirects, DNS works, and routing correctly uses
# Wi-Fi, but a portal in Tailscale's range times out. Full mode must stop here.
run_case amtrak 1
contains 'LIKELY CAUSE: Tailscale filtering'
contains 'dev wlp2s0'
contains 'sudo systemctl stop tailscaled'
contains 'sudo systemctl start tailscaled'
contains 'automatic sign-in detection is disabled'
absent 'Public HTTPS sites'
if grep -q 'speed.cloudflare.com' "$NETWORK_TEST_LOG"; then
  printf 'FAIL: attempted a speed test before portal sign-in\n' >&2
  exit 1
fi

run_case clear 0 --portal-only
contains 'expected 204'
absent 'LIKELY CAUSE'
absent 'Internet protocol support'

run_case reachable 1 --portal-only
contains 'Login page is reachable'
contains 'filtering is not demonstrated'
absent 'LIKELY CAUSE'
absent 'sudo systemctl stop'

run_case no-tailscale 1 --portal-only
contains 'no tailscale0 interface was found'
absent 'LIKELY CAUSE'

run_case private-portal 1 --portal-only
contains '192.168.10.1'
contains 'Login page is reachable'
absent 'overlaps Tailscale'

for scenario in lower-boundary upper-boundary; do
  run_case "$scenario" 1 --portal-only
  absent 'overlaps Tailscale'
  absent 'LIKELY CAUSE'
done

run_case last-cgnat 1 --portal-only
contains 'LIKELY CAUSE'

run_case redirect-chain 1 --portal-only
contains 'final.example.test -> 100.64.1.2'
contains 'LIKELY CAUSE'

run_case tls 1 --portal-only
contains 'TLS certificate verification failed'
absent 'LIKELY CAUSE'

run_case dns 1 --portal-only
contains 'No IPv4 DNS answer'
absent 'LIKELY CAUSE'

run_case inline 1 --portal-only
contains 'possible sign-in page'
contains 'http://neverssl.com/'
absent 'LIKELY CAUSE'

run_case probe-failure 1 --portal-only
contains 'Wi-Fi sign-in probe failed'
absent 'LIKELY CAUSE'

run_case amtrak 1 --portal-only --portal-url https://login.example.test/
contains 'LIKELY CAUSE'
if grep -q 'connectivitycheck.gstatic.com' "$NETWORK_TEST_LOG"; then
  printf 'FAIL: probed public HTTP despite an explicit portal URL\n' >&2
  exit 1
fi

run_case clear 2 --timeout 0
contains 'positive integer'

run_case clear 2 --timeout
contains 'positive integer'

run_case clear 2 --portal-url --portal-only
contains 'requires an HTTP(S) URL'

run_case clear 2 --portal-url
contains 'requires an HTTP(S) URL'

printf 'PASS: %s network diagnosis scenarios (no network access or configuration changes)\n' "$cases"
