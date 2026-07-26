#!/usr/bin/env bash

# Read-only network diagnostics for Linux.
# Approximate speed-test defaults: 25 MB download + 10 MB upload.

set -u

TIMEOUT_SECONDS=10
DOWNLOAD_BYTES=25000000
UPLOAD_BYTES=10000000
RUN_SPEED_TEST=1
UDP_ECHO_HOST="65.21.106.102"
UDP_ECHO_PORT=8080

usage() {
  cat <<'EOF'
Usage: network-diagnostics.sh [options]

Options:
  --skip-speed             Skip the Cloudflare transfer test
  --download-bytes NUMBER  Download size (default: 25000000)
  --upload-bytes NUMBER    Upload size (default: 10000000)
  --timeout SECONDS        Per-check timeout (default: 10)
  -h, --help               Show this help
EOF
}

while (($#)); do
  case "$1" in
    --skip-speed)
      RUN_SPEED_TEST=0
      shift
      ;;
    --download-bytes)
      DOWNLOAD_BYTES="${2:?missing byte count}"
      shift 2
      ;;
    --upload-bytes)
      UPLOAD_BYTES="${2:?missing byte count}"
      shift 2
      ;;
    --timeout)
      TIMEOUT_SECONDS="${2:?missing timeout}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v curl >/dev/null; then
  printf 'ERROR: curl is required.\n' >&2
  exit 1
fi

pass_count=0
fail_count=0
warn_count=0

section() {
  printf '\n== %s ==\n' "$1"
}

pass() {
  pass_count=$((pass_count + 1))
  printf '[PASS] %s\n' "$*"
}

fail() {
  fail_count=$((fail_count + 1))
  printf '[FAIL] %s\n' "$*"
}

warn() {
  warn_count=$((warn_count + 1))
  printf '[WARN] %s\n' "$*"
}

dns_probe() {
  local host="$1"
  local result

  if command -v getent >/dev/null; then
    result="$(getent ahostsv4 "$host" 2>&1 | awk 'NR == 1 { print $1 }')"
    if [[ -n "$result" ]]; then
      pass "DNS resolution for $host: $result"
    else
      fail "DNS resolution for $host failed"
    fi
  else
    warn "DNS resolution check skipped: getent is unavailable"
  fi
}

stun_probe() {
  local label="$1"
  local host="$2"
  local port="$3"
  local response_bytes

  if ! command -v nc >/dev/null || ! command -v timeout >/dev/null; then
    warn "$label skipped: nc and timeout are required"
    return
  fi

  # STUN binding request: type, zero payload length, magic cookie, transaction ID.
  response_bytes="$(
    printf '\x00\x01\x00\x00\x21\x12\xa4\x42\x4e\x45\x54\x44\x49\x41\x47\x30\x30\x30\x31\x21' |
      timeout "$((TIMEOUT_SECONDS + 1))" nc -u -w "$TIMEOUT_SECONDS" "$host" "$port" 2>/dev/null |
      wc -c
  )"
  response_bytes="${response_bytes//[[:space:]]/}"

  if [[ "$response_bytes" =~ ^[0-9]+$ ]] && ((response_bytes >= 20)); then
    pass "$label: received a ${response_bytes}-byte UDP STUN response from $host:$port"
  else
    fail "$label: no valid UDP response from $host:$port (blocked, timed out, or endpoint unavailable)"
  fi
}

udp_echo_probe() {
  local token="network-diagnostics-$RANDOM-$$"
  local output

  if ! command -v nc >/dev/null || ! command -v timeout >/dev/null; then
    warn "Public UDP echo skipped: nc and timeout are required"
    return
  fi

  output="$(
    printf '%s\n' "$token" |
      timeout "$((TIMEOUT_SECONDS + 1))" nc -u -w "$TIMEOUT_SECONDS" \
        "$UDP_ECHO_HOST" "$UDP_ECHO_PORT" 2>&1
  )"

  if [[ "$output" == *"$token"* ]]; then
    pass "Public UDP echo: received a reply from $UDP_ECHO_HOST:$UDP_ECHO_PORT"
  else
    fail "Public UDP echo: no reply from $UDP_ECHO_HOST:$UDP_ECHO_PORT (blocked, timed out, or endpoint unavailable)"
  fi
}

http3_probe() {
  local resolved_ip
  local result
  local rc
  local code
  local version
  local remote_ip
  local elapsed

  if ! curl --version | grep --quiet --word-regexp HTTP3; then
    warn "HTTP/3 test skipped: this curl build lacks HTTP/3 support"
    return
  fi

  # Resolve over the ordinary HTTPS-capable path first, then pin that address.
  # This keeps DNS failure separate from the subsequent UDP/443 QUIC test.
  resolved_ip="$(
    curl -4 --http1.1 --silent --show-error --output /dev/null \
      --connect-timeout "$TIMEOUT_SECONDS" --max-time "$TIMEOUT_SECONDS" \
      --write-out '%{remote_ip}' https://cloudflare.com/cdn-cgi/trace 2>/dev/null
  )"
  if [[ -z "$resolved_ip" ]]; then
    fail "HTTP/3 prerequisite: could not resolve and reach cloudflare.com over IPv4 HTTPS"
    return
  fi

  result="$(
    curl -4 --http3-only --silent --show-error --output /dev/null \
      --connect-timeout "$TIMEOUT_SECONDS" --max-time "$TIMEOUT_SECONDS" \
      --resolve "cloudflare.com:443:$resolved_ip" \
      --write-out $'\n%{http_code}|%{http_version}|%{remote_ip}|%{time_total}' \
      https://cloudflare.com/cdn-cgi/trace 2>&1
  )"
  rc=$?

  if ((rc != 0)); then
    fail "HTTP/3 over UDP/443 failed after DNS was bypassed: ${result//$'\n'/ }"
    return
  fi

  IFS='|' read -r code version remote_ip elapsed <<<"$(tail -n 1 <<<"$result")"
  if [[ "$version" == "3" && "$code" =~ ^[1-4][0-9][0-9]$ ]]; then
    pass "HTTP/3 over UDP/443: HTTP $code via $remote_ip in ${elapsed}s"
  else
    warn "HTTP/3 returned unexpected result: HTTP $code, version $version, via $remote_ip"
  fi
}

http_probe() {
  local label="$1"
  local url="$2"
  local result
  local rc
  local code
  local remote_ip
  local elapsed

  result="$(
    curl --head --location --silent --show-error --output /dev/null \
      --max-time "$TIMEOUT_SECONDS" \
      --write-out '%{http_code}|%{remote_ip}|%{time_total}' \
      "$url" 2>&1
  )"
  rc=$?

  if ((rc != 0)); then
    fail "$label ($url): $result"
    return
  fi

  IFS='|' read -r code remote_ip elapsed <<<"$result"
  if [[ "$code" =~ ^[1-4][0-9][0-9]$ ]]; then
    pass "$label: HTTP $code via $remote_ip in ${elapsed}s"
  else
    warn "$label is reachable but returned HTTP $code via $remote_ip in ${elapsed}s"
  fi
}

ip_family_probe() {
  local family="$1"
  local curl_flag="$2"
  local result
  local rc
  local public_ip
  local colo

  result="$(
    curl "$curl_flag" --location --silent --show-error \
      --max-time "$TIMEOUT_SECONDS" \
      https://one.one.one.one/cdn-cgi/trace 2>&1
  )"
  rc=$?

  if ((rc != 0)); then
    fail "$family Internet connectivity: $result"
    return
  fi

  public_ip="$(sed -n 's/^ip=//p' <<<"$result" | head -n 1)"
  colo="$(sed -n 's/^colo=//p' <<<"$result" | head -n 1)"
  pass "$family Internet connectivity: public IP ${public_ip:-unknown}, Cloudflare colo ${colo:-unknown}"
}

tcp_probe() {
  local label="$1"
  local host="$2"
  local port="$3"

  if ! command -v timeout >/dev/null; then
    warn "$label TCP check skipped: timeout command is unavailable"
    return 2
  fi

  if timeout "$TIMEOUT_SECONDS" bash -c \
    'exec 3<>"/dev/tcp/$1/$2"' _ "$host" "$port" 2>/dev/null; then
    pass "$label: TCP $host:$port is reachable"
    return 0
  fi

  fail "$label: TCP $host:$port is blocked, refused, or timed out"
  return 1
}

ssh_probe() {
  local label="$1"
  local target="$2"
  local kind="$3"
  local output
  local rc

  if ! command -v ssh >/dev/null; then
    warn "$label authentication skipped: ssh is unavailable"
    return
  fi

  if [[ "$kind" == "forge" ]]; then
    output="$(
      ssh -T \
        -o BatchMode=yes \
        -o ConnectTimeout="$TIMEOUT_SECONDS" \
        -o ConnectionAttempts=1 \
        -o StrictHostKeyChecking=yes \
        "$target" 2>&1
    )"
    rc=$?
  else
    output="$(
      ssh \
        -o BatchMode=yes \
        -o ConnectTimeout="$TIMEOUT_SECONDS" \
        -o ConnectionAttempts=1 \
        -o StrictHostKeyChecking=yes \
        "$target" true 2>&1
    )"
    rc=$?
  fi

  if ((rc == 0)) ||
    grep --quiet --extended-regexp \
      'successfully authenticated|successfully authenticated with the key|does not provide shell access' \
      <<<"$output"; then
    pass "$label: SSH authentication succeeded"
  elif grep --quiet --extended-regexp \
    'Host key verification failed|No .* host key is known' <<<"$output"; then
    warn "$label: transport worked, but the host key is not already trusted; verify it manually before authenticating"
  elif grep --quiet --extended-regexp \
    'Permission denied|authentication failed' <<<"$output"; then
    fail "$label: transport worked, but SSH authentication failed"
  else
    fail "$label SSH attempt: ${output:-exit status $rc}"
  fi
}

cloudflare_speed_test() {
  local temp_file
  local download_result
  local upload_result
  local rc
  local speed
  local elapsed
  local mbps

  temp_file="$(mktemp "${TMPDIR:-/tmp}/network-speed.XXXXXXXX")" || {
    fail "Cloudflare speed test: could not create temporary file"
    return
  }

  printf 'Using approximately %.1f MB download and %.1f MB upload.\n' \
    "$((DOWNLOAD_BYTES / 1000000))" "$((UPLOAD_BYTES / 1000000))"

  download_result="$(
    curl --silent --show-error --output /dev/null \
      --max-time 120 \
      --retry 2 \
      --retry-all-errors \
      --write-out '%{speed_download}|%{time_total}|%{http_code}' \
      "https://speed.cloudflare.com/__down?bytes=$DOWNLOAD_BYTES" 2>&1
  )"
  rc=$?
  if ((rc == 0)); then
    IFS='|' read -r speed elapsed code <<<"$download_result"
    mbps="$(awk -v bytes_per_second="$speed" 'BEGIN { printf "%.2f", bytes_per_second * 8 / 1000000 }')"
    pass "Cloudflare download estimate: ${mbps} Mbps (${elapsed}s, HTTP $code)"
  else
    fail "Cloudflare download test: $download_result"
  fi

  truncate --size "$UPLOAD_BYTES" "$temp_file"
  upload_result="$(
    curl --silent --show-error --output /dev/null \
      --max-time 120 \
      --retry 2 \
      --retry-all-errors \
      --request POST \
      --header 'Content-Type: application/octet-stream' \
      --data-binary "@$temp_file" \
      --write-out '%{speed_upload}|%{time_total}|%{http_code}' \
      https://speed.cloudflare.com/__up 2>&1
  )"
  rc=$?
  if ((rc == 0)); then
    IFS='|' read -r speed elapsed code <<<"$upload_result"
    mbps="$(awk -v bytes_per_second="$speed" 'BEGIN { printf "%.2f", bytes_per_second * 8 / 1000000 }')"
    pass "Cloudflare upload estimate: ${mbps} Mbps (${elapsed}s, HTTP $code)"
  else
    fail "Cloudflare upload test: $upload_result"
  fi

  rm -f "$temp_file"
}

printf 'Network diagnostics started: %s\n' "$(date --iso-8601=seconds)"
printf 'Host: %s\n' "$(hostname)"

section "Local addressing and routes"
if command -v ip >/dev/null; then
  ip -brief address
  printf '\nIPv4 default route:\n'
  ip -4 route show default || true
  printf 'IPv6 default route:\n'
  ip -6 route show default || true
else
  warn "ip command is unavailable; skipping local address and route display"
fi

section "Internet protocol support"
ip_family_probe "IPv4" "-4"
ip_family_probe "IPv6" "-6"

section "DNS and unauthenticated UDP reachability"
dns_probe "cloudflare.com"
stun_probe "Cloudflare STUN" "stun.cloudflare.com" 3478
stun_probe "Google STUN" "stun.l.google.com" 19302
udp_echo_probe
http3_probe
printf 'STUN tests general UDP replies; HTTP/3 tests QUIC over UDP/443; UDP echo tests a separate destination and port.\n'
printf 'One failed endpoint can be down. Multiple UDP failures while HTTPS works strongly suggest network filtering.\n'

section "Public HTTPS sites"
http_probe "Cloudflare" "https://www.cloudflare.com/"
http_probe "Codeberg" "https://codeberg.org/"
http_probe "GitHub" "https://github.com/"
http_probe "Wikipedia" "https://www.wikipedia.org/"

section "Proton reachability"
http_probe "Proton VPN website" "https://protonvpn.com/"
http_probe "Proton account service" "https://account.protonvpn.com/"
http_probe "Proton VPN API" "https://api.protonvpn.ch/"

section "SSH transport and authentication"
if tcp_probe "Codeberg SSH" "codeberg.org" 22; then
  ssh_probe "Codeberg" "git@codeberg.org" "forge"
fi
if tcp_probe "GitHub SSH" "github.com" 22; then
  ssh_probe "GitHub" "git@github.com" "forge"
fi
if tcp_probe "Personal VPS SSH" "salehhassen.xyz" 22; then
  ssh_probe "Personal VPS" "saleh@salehhassen.xyz" "shell"
fi
tcp_probe "GitHub SSH-over-HTTPS fallback" "ssh.github.com" 443 || true

if command -v protonvpn >/dev/null; then
  section "Proton VPN client"
  protonvpn status || warn "The Proton VPN CLI is installed but did not return status"
fi

if ((RUN_SPEED_TEST)); then
  section "Cloudflare CLI speed estimate"
  cloudflare_speed_test
else
  section "Cloudflare CLI speed estimate"
  warn "Skipped by --skip-speed"
fi

section "Summary"
printf 'PASS=%d  WARN=%d  FAIL=%d\n' "$pass_count" "$warn_count" "$fail_count"
printf 'A failed IPv6 check is normal on IPv4-only networks.\n'
printf 'Cloudflare speed figures are single-transfer estimates, not the full browser test methodology.\n'

((fail_count == 0))
