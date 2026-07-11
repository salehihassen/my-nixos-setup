#!/usr/bin/env bash
set -euo pipefail

REPO_SOURCE="${REPO_SOURCE:-/etc/nixos-recovery/source}"
WORK_DIR="${WORK_DIR:-/tmp/nixos-recovery}"
ACTION_DIR="$WORK_DIR/actions"

mkdir -p "$ACTION_DIR"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

show_storage() {
  printf '\nDetected disks and partitions:\n\n'
  lsblk -e7 -o NAME,PATH,SIZE,TYPE,FSTYPE,FSVER,LABEL,PARTLABEL,PARTUUID,UUID,MOUNTPOINTS,MODEL

  printf '\nLikely installed OS signals:\n\n'
  lsblk -rpno PATH,FSTYPE,LABEL,PARTLABEL,SIZE,MOUNTPOINTS |
    awk '
      BEGIN { found = 0 }
      /vfat|fat32|EFI|ESP/ { print "EFI/ESP candidate:     " $0; found = 1 }
      /ntfs|BitLocker|Windows|Basic data/ { print "Windows candidate:     " $0; found = 1 }
      /ext4|btrfs|xfs|crypto_LUKS|LVM2_member/ { print "Linux candidate:       " $0; found = 1 }
      /swap/ { print "Swap candidate:        " $0; found = 1 }
      END { if (found == 0) print "No obvious existing OS partitions detected by simple filesystem/label scan." }
    '
}

prompt_nonempty() {
  local prompt="$1"
  local value
  while true; do
    read -r -p "$prompt" value
    if [[ -n "$value" ]]; then
      printf '%s\n' "$value"
      return
    fi
  done
}

prompt_mode() {
  local mode
  while true; do
    read -r -p "Install mode [multiboot/single-boot-destructive]: " mode
    case "$mode" in
      multiboot|single-boot-destructive)
        printf '%s\n' "$mode"
        return
        ;;
      *)
        printf 'Choose exactly: multiboot or single-boot-destructive\n'
        ;;
    esac
  done
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

confirm_disk() {
  local disk="$1"
  [[ -b "$disk" ]] || die "$disk is not a block device"

  printf '\nSelected target disk details:\n\n'
  lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,PARTLABEL,UUID,MOUNTPOINTS,MODEL "$disk"

  local confirm
  read -r -p "Type the exact disk path to confirm target disk ($disk): " confirm
  [[ "$confirm" == "$disk" ]] || die "target disk confirmation did not match"
}

write_single_boot_script() {
  local disk="$1"
  local hostname="$2"
  local username="$3"
  local passphrase_name="$4"
  local script="$ACTION_DIR/01-single-boot-destructive.sh"

  cat > "$script" <<EOF
#!/usr/bin/env bash
set -euo pipefail

disk="$disk"
hostname="$hostname"
username="$username"
mapper="$passphrase_name"

echo "This will wipe \$disk and create a NixOS-only installation."
read -r -p "Type WIPE \$disk to continue: " confirm
if [[ "\$confirm" != "WIPE \$disk" ]]; then
  echo "confirmation failed" >&2
  exit 1
fi

swapoff --all || true
umount -R /mnt 2>/dev/null || true
cryptsetup close "\$mapper" 2>/dev/null || true

wipefs -a "\$disk"
sgdisk --zap-all "\$disk"
parted --script "\$disk" \\
  mklabel gpt \\
  mkpart ESP fat32 1MiB 1025MiB \\
  set 1 esp on \\
  mkpart boot ext4 1025MiB 3073MiB \\
  mkpart nixos 3073MiB -16GiB \\
  mkpart swap linux-swap -16GiB 100%

partprobe "\$disk"
sleep 2

efi="\${disk}1"
boot="\${disk}2"
rootpart="\${disk}3"
swappart="\${disk}4"
if [[ "\$disk" =~ (nvme|mmcblk|loop) ]]; then
  efi="\${disk}p1"
  boot="\${disk}p2"
  rootpart="\${disk}p3"
  swappart="\${disk}p4"
fi

mkfs.vfat -F 32 -n EFI "\$efi"
mkfs.ext4 -F -L nixboot "\$boot"
cryptsetup luksFormat "\$rootpart"
cryptsetup open "\$rootpart" "\$mapper"
mkfs.btrfs -f -L nixroot "/dev/mapper/\$mapper"
mkswap -L nixswap "\$swappart"

mount "/dev/mapper/\$mapper" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@nix
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@snapshots
umount /mnt

mount -o subvol=@ "/dev/mapper/\$mapper" /mnt
mkdir -p /mnt/{home,nix,var/log,.snapshots,boot/efi}
mount -o subvol=@home "/dev/mapper/\$mapper" /mnt/home
mount -o subvol=@nix "/dev/mapper/\$mapper" /mnt/nix
mount -o subvol=@log "/dev/mapper/\$mapper" /mnt/var/log
mount -o subvol=@snapshots "/dev/mapper/\$mapper" /mnt/.snapshots
mount "\$boot" /mnt/boot
mkdir -p /mnt/boot/efi
mount "\$efi" /mnt/boot/efi
swapon "\$swappart"

nixos-generate-config --root /mnt
EOF

  chmod +x "$script"
  printf '%s\n' "$script"
}

write_multiboot_notes() {
  local disk="$1"
  local hostname="$2"
  local username="$3"
  local notes="$ACTION_DIR/01-multiboot-mount-commands.txt"

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

  printf '%s\n' "$notes"
}

copy_repo_and_template() {
  local hostname="$1"
  local username="$2"

  [[ -d /mnt ]] || die "/mnt does not exist"
  mountpoint -q /mnt || die "/mnt is not mounted"
  [[ -f /mnt/etc/nixos/hardware-configuration.nix ]] || die "run nixos-generate-config --root /mnt first"
  [[ -d "$REPO_SOURCE" ]] || die "repo source not found at $REPO_SOURCE"

  mkdir -p /mnt/etc/nixos
  rsync -a --delete --exclude result --exclude .git "$REPO_SOURCE"/ /mnt/etc/nixos/
  mkdir -p /mnt/etc/nixos/hosts
  cp /mnt/etc/nixos/hardware-configuration.nix "/mnt/etc/nixos/hosts/$hostname-hardware.nix"
  cp /mnt/etc/nixos/templates/new-computer.nix "/mnt/etc/nixos/hosts/$hostname.nix"

  sed -i \
    -e "s#./hardware-configuration.nix#./$hostname-hardware.nix#" \
    -e "s#lib.mkDefault \"new-computer\"#\"$hostname\"#" \
    -e "s#username ? \"saleh\"#username ? \"$username\"#" \
    "/mnt/etc/nixos/hosts/$hostname.nix"
}

print_finish_commands() {
  local hostname="$1"
  local username="$2"
  local finish="$ACTION_DIR/02-finish-install.sh"

  cat > "$finish" <<EOF
#!/usr/bin/env bash
set -euo pipefail

cd /mnt/etc/nixos
nixos-install --flake ".#$hostname"
echo "Set the target user password after install:"
echo "  passwd $username"
EOF

  chmod +x "$finish"

  printf '\nTarget repo and host files are prepared under /mnt/etc/nixos.\n'
  printf 'A final privileged install script was written to:\n\n  %s\n\n' "$finish"
  printf 'Run it externally with sudo because it installs the bootloader, writes the target system, and changes the mounted target OS:\n\n'
  printf '  sudo bash %s\n\n' "$finish"
  printf 'After nixos-install completes, run this in the target or via nixos-enter to set the password:\n\n'
  printf '  passwd %s\n\n' "$username"
}

finish_existing_mount() {
  local hostname="$1"
  local username="$2"

  validate_hostname "$hostname"
  validate_username "$username"
  copy_repo_and_template "$hostname" "$username"

  if ! grep -q "^[[:space:]]*$hostname = .*./hosts/$hostname.nix" /mnt/etc/nixos/flake.nix; then
    grep -q "^[[:space:]]*b1 = mkHost ./hosts/b1.nix;" /mnt/etc/nixos/flake.nix ||
      die "could not find nixosConfigurations insertion point in flake.nix"
    sed -i "/^[[:space:]]*b1 = mkHost \\.\\/hosts\\/b1\\.nix;/a\\      $hostname = mkHostFor { hostModule = ./hosts/$hostname.nix; username = \"$username\"; };" /mnt/etc/nixos/flake.nix
  fi

  print_finish_commands "$hostname" "$username"
}

usage() {
  cat <<'EOF'
Usage:
  nixos-recovery-install
  nixos-recovery-install --finish --hostname <name> --username <user>

The default flow inspects disks and writes operator-run scripts for partitioning
and installation. Privileged disk writes are printed as sudo commands/scripts for
manual execution.
EOF
}

main() {
  need_cmd lsblk
  need_cmd rsync

  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
  fi

  if [[ "${1:-}" == "--finish" ]]; then
    shift
    local hostname=""
    local username=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --hostname)
          hostname="${2:-}"
          shift 2
          ;;
        --username)
          username="${2:-}"
          shift 2
          ;;
        *)
          die "unknown argument: $1"
          ;;
      esac
    done
    [[ -n "$hostname" ]] || die "--hostname is required"
    [[ -n "$username" ]] || die "--username is required"
    finish_existing_mount "$hostname" "$username"
    exit 0
  fi

  show_storage

  local mode username hostname disk
  mode="$(prompt_mode)"
  username="$(prompt_nonempty "Target Linux username [example: saleh]: ")"
  hostname="$(prompt_nonempty "Target hostname [example: b2]: ")"
  disk="$(prompt_nonempty "Target disk path [example: /dev/nvme0n1]: ")"
  validate_username "$username"
  validate_hostname "$hostname"
  confirm_disk "$disk"

  case "$mode" in
    single-boot-destructive)
      local mapper script
      mapper="$(prompt_nonempty "LUKS mapper name [example: cryptnix]: ")"
      validate_mapper_name "$mapper"
      script="$(write_single_boot_script "$disk" "$hostname" "$username" "$mapper")"
      printf '\nA destructive privileged disk setup script was written to:\n\n  %s\n\n' "$script"
      printf 'Review it first. Run it externally with sudo only if you intend to wipe %s:\n\n' "$disk"
      printf '  sudo bash %s\n\n' "$script"
      printf 'Then finish the repo/config install step:\n\n'
      printf '  nixos-recovery-install --finish --hostname %s --username %s\n\n' "$hostname" "$username"
      ;;
    multiboot)
      local notes
      notes="$(write_multiboot_notes "$disk" "$hostname" "$username")"
      printf '\nMultiboot instructions were written to:\n\n  %s\n\n' "$notes"
      printf 'Create and mount only new NixOS partitions, then run:\n\n'
      printf '  nixos-recovery-install --finish --hostname %s --username %s\n\n' "$hostname" "$username"
      ;;
  esac
}

main "$@"
