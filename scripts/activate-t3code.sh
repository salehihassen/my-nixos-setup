#!/usr/bin/env bash
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "Run with sudo: sudo bash /etc/nixos/scripts/activate-t3code.sh" >&2
  exit 1
fi

# Staged outside the checkout, never evaluated or copied into the Nix store.
source_dir=/home/saleh/.local/share/t3code-provisioning
test -s "$source_dir/porkbun.env"
install -d -m 0755 /etc/caddy
install -o root -g root -m 0600 "$source_dir/porkbun.env" /etc/caddy/porkbun.env
nixos-rebuild switch --flake /etc/nixos#j2 --cores 4 --max-jobs 1
loginctl enable-linger saleh

# The source copy is no longer needed once systemd has its root-only file.
rm -f "$source_dir/porkbun.env" "$source_dir/porkbun_api_key" "$source_dir/porkbun_api_secret_key"
echo "T3 Code and Caddy configuration activated."
