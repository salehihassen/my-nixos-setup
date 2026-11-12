#!/usr/bin/env bash
# Validate/build without activation; elevate only explicit activation operations.
set -euo pipefail

usage() {
  echo 'Usage: nixos-maintain.sh check|build|test|switch|boot|update [HOST]' >&2
}

if (( $# < 1 || $# > 2 )); then usage; exit 2; fi
operation=$1
case "$operation" in
  check|build|test|switch|boot|update) ;;
  -h|--help) usage; exit 0 ;;
  *) usage; exit 2 ;;
esac

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
host=${2-$(hostname -s)}
if [[ ! $host =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
  echo "Invalid host: $host" >&2
  exit 2
fi

# List the flake's exported hosts, without maintaining another host registry.
hosts=$(nix eval --raw --no-update-lock-file \
  --apply 'configs: builtins.concatStringsSep "\n" (builtins.attrNames configs)' \
  "$root#nixosConfigurations")
found=false
while IFS= read -r configured; do
  if [[ $configured == "$host" ]]; then found=true; break; fi
done <<< "$hosts"
if [[ $found == false ]]; then
  echo "Unknown host: $host. Configured hosts:" >&2
  echo "$hosts" >&2
  exit 2
fi

# Keep rebuild's result link in this checkout even when invoked from elsewhere.
cd -- "$root"
check() {
  nix flake check --no-build --no-update-lock-file "$root"
}
build() {
  nixos-rebuild build --flake "$root#$host" --no-update-lock-file --max-jobs 2 --cores 4
}

case "$operation" in
  check) check ;;
  build) build ;;
  test|switch|boot)
    sudo nixos-rebuild "$operation" --flake "$root#$host" \
      --no-update-lock-file --max-jobs 2 --cores 4
    ;;
  update)
    nix flake update nixpkgs home-manager --flake "$root"
    git -C "$root" diff -- flake.lock
    check
    build
    ;;
esac
