#!/usr/bin/env bash
set -euo pipefail

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

validate_mapper_name() {
  local mapper="$1"
  [[ "$mapper" =~ ^[A-Za-z0-9._-]+$ ]] ||
    die "LUKS mapper name must contain only letters, numbers, dots, underscores, or hyphens"
}

usage() {
  cat <<'EOF'
Usage:
  nixos-recovery-single-boot-destructive --disk <disk> --hostname <name> --username <user> --mapper <name>

Wipes the selected disk, creates a NixOS-only encrypted btrfs layout, mounts it
under /mnt, and runs nixos-generate-config --root /mnt.
EOF
}

disk=""
hostname=""
username=""
mapper=""

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
    --mapper)
      mapper="${2:-}"
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
[[ -n "$mapper" ]] || die "--mapper is required"
[[ -b "$disk" ]] || die "$disk is not a block device"
validate_hostname "$hostname"
validate_username "$username"
validate_mapper_name "$mapper"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  die "run this command with sudo because it partitions, formats, and mounts the target disk"
fi

printf '\nSelected target disk details:\n\n'
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,PARTLABEL,UUID,MOUNTPOINTS,MODEL "$disk"

printf '\nThis will wipe %s and create a NixOS-only installation for host %s and user %s.\n' "$disk" "$hostname" "$username"
read -r -p "Type WIPE $disk to continue: " confirm
[[ "$confirm" == "WIPE $disk" ]] || die "confirmation failed"

swapoff --all || true
umount -R /mnt 2>/dev/null || true
cryptsetup close "$mapper" 2>/dev/null || true

wipefs -a "$disk"
sgdisk --zap-all "$disk"
parted --script "$disk" \
  mklabel gpt \
  mkpart ESP fat32 1MiB 1025MiB \
  set 1 esp on \
  mkpart boot ext4 1025MiB 3073MiB \
  mkpart nixos 3073MiB -16GiB \
  mkpart swap linux-swap -16GiB 100%

partprobe "$disk"
sleep 2

efi="${disk}1"
boot="${disk}2"
rootpart="${disk}3"
swappart="${disk}4"
if [[ "$disk" =~ (nvme|mmcblk|loop) ]]; then
  efi="${disk}p1"
  boot="${disk}p2"
  rootpart="${disk}p3"
  swappart="${disk}p4"
fi

mkfs.vfat -F 32 -n EFI "$efi"
mkfs.ext4 -F -L nixboot "$boot"
cryptsetup luksFormat "$rootpart"
cryptsetup open "$rootpart" "$mapper"
mkfs.btrfs -f -L nixroot "/dev/mapper/$mapper"
mkswap -L nixswap "$swappart"

mount "/dev/mapper/$mapper" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@nix
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@snapshots
umount /mnt

mount -o subvol=@ "/dev/mapper/$mapper" /mnt
mkdir -p /mnt/{home,nix,var/log,.snapshots,boot/efi}
mount -o subvol=@home "/dev/mapper/$mapper" /mnt/home
mount -o subvol=@nix "/dev/mapper/$mapper" /mnt/nix
mount -o subvol=@log "/dev/mapper/$mapper" /mnt/var/log
mount -o subvol=@snapshots "/dev/mapper/$mapper" /mnt/.snapshots
mount "$boot" /mnt/boot
mkdir -p /mnt/boot/efi
mount "$efi" /mnt/boot/efi
swapon "$swappart"

nixos-generate-config --root /mnt

printf '\nDisk setup complete. Finish the install with:\n\n'
printf '  nixos-recovery-install --finish --hostname %s --username %s\n\n' "$hostname" "$username"
