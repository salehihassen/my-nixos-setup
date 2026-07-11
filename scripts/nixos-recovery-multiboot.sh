#!/usr/bin/env bash
set -euo pipefail

WORK_DIR="${WORK_DIR:-/tmp/nixos-recovery}"
ACTION_DIR="$WORK_DIR/actions"

mkdir -p "$ACTION_DIR"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

validate_hostname() {
  local hostname="$1"
  [[ "$hostname" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,62}$ ]] ||
    die "hostname must contain only letters, numbers, and hyphens, and cannot start with a hyphen"
}

validate_username() {
  local username="$1"
  [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] ||
    die "username must be a normal Linux user name: lowercase letters, digits, underscore, or hyphen"
}

usage() {
  cat <<'EOF'
Usage:
  nixos-recovery-multiboot --disk <disk> --hostname <name> --username <user>

Writes non-destructive multiboot mount guidance. It does not partition, resize,
format, or mount existing OS partitions.
EOF
}

disk=""
hostname=""
username=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --disk)
      disk="${2:-}"
      shift 2
      ;;
    --hostname)
      hostname="${2:-}"
      shift 2
      ;;
    --username)
      username="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$disk" ]] || die "--disk is required"
[[ -n "$hostname" ]] || die "--hostname is required"
[[ -n "$username" ]] || die "--username is required"
[[ -b "$disk" ]] || die "$disk is not a block device"
validate_hostname "$hostname"
validate_username "$username"

notes="$ACTION_DIR/01-multiboot-mount-commands.txt"

cat > "$notes" <<EOF
Multiboot mode selected for $disk.

This helper intentionally does not partition, resize, format, or mount existing
OS partitions for you. Use a partitioning tool to create Linux partitions only
in confirmed free space. Do not format Windows, existing Linux, recovery, or EFI
partitions.

After creating the target NixOS partitions, mount them under /mnt. Example shape:

  sudo cryptsetup luksFormat /dev/<new-linux-root-partition>
  sudo cryptsetup open /dev/<new-linux-root-partition> cryptnix
  sudo mkfs.btrfs -f -L nixroot /dev/mapper/cryptnix
  sudo mount /dev/mapper/cryptnix /mnt
  sudo btrfs subvolume create /mnt/@
  sudo btrfs subvolume create /mnt/@home
  sudo btrfs subvolume create /mnt/@nix
  sudo btrfs subvolume create /mnt/@log
  sudo btrfs subvolume create /mnt/@snapshots
  sudo umount /mnt
  sudo mount -o subvol=@ /dev/mapper/cryptnix /mnt
  sudo mkdir -p /mnt/{home,nix,var/log,.snapshots,boot/efi}
  sudo mount -o subvol=@home /dev/mapper/cryptnix /mnt/home
  sudo mount -o subvol=@nix /dev/mapper/cryptnix /mnt/nix
  sudo mount -o subvol=@log /dev/mapper/cryptnix /mnt/var/log
  sudo mount -o subvol=@snapshots /dev/mapper/cryptnix /mnt/.snapshots
  sudo mount /dev/<existing-efi-partition> /mnt/boot/efi
  sudo nixos-generate-config --root /mnt

Existing EFI should only be mounted after confirming it is the correct ESP.
Do not run mkfs.* against existing EFI or OS partitions in multiboot mode.

Then rerun:

  nixos-recovery-install --finish --hostname $hostname --username $username
EOF

printf '\nMultiboot instructions were written to:\n\n  %s\n\n' "$notes"
printf 'Create and mount only new NixOS partitions, then run:\n\n'
printf '  nixos-recovery-install --finish --hostname %s --username %s\n\n' "$hostname" "$username"
