{ config, lib, pkgs, inputs, self, ... }:

let
  repoSource = lib.cleanSourceWith {
    src = ../.;
    filter = path: type:
      let
        name = baseNameOf path;
      in
        !(name == ".git" || name == "result");
  };
in
{
  imports = [
    "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  isoImage.edition = lib.mkForce "recovery";

  # GLIM expects this entry point. The generated EFI menu already handles
  # iso_path by passing findiso= to the installer kernel. Source it so the
  # wrapper can restore GLIM's selected device after the native marker search.
  isoImage.contents = [
    {
      source = pkgs.writeText "nixos-recovery-loopback.cfg" ''
        source /EFI/BOOT/grub.cfg
        if [ -n "''${glim_isodev}" ]; then
          set root="''${glim_isodev}"
        fi
      '';
      target = "/boot/grub/loopback.cfg";
    }
  ];

  # The systemd initrd otherwise waits for a physical ISO volume even when
  # GRUB supplies findiso=. Attach that file read-only so its normal label-based
  # /iso mount and squashfs store can proceed unchanged.
  boot.initrd.availableKernelModules = [ "vfat" "nls_cp437" "nls_iso8859-1" ];
  boot.initrd.systemd.services.glim-findiso = {
    description = "Attach the NixOS installer ISO from a multiboot USB";
    requiredBy = [ "initrd.target" ];
    before = [ "sysroot-iso.mount" ];
    after = [ "systemd-udevd.service" ];
    requires = [ "systemd-udevd.service" ];
    unitConfig = {
      DefaultDependencies = false;
      ConditionKernelCommandLine = "findiso";
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = 45;
    };
    path = [ pkgs.coreutils pkgs.util-linux pkgs.kmod config.boot.initrd.systemd.package ];
    script = ''
      set -eu
      isofile=
      for option in $(cat /proc/cmdline); do
        case "$option" in findiso=*) isofile="''${option#findiso=}" ;; esac
      done
      [ -n "$isofile" ] || exit 0
      case "$isofile" in /*) ;; *) echo "GLIM: findiso must be an absolute path" >&2; exit 1 ;; esac

      modprobe vfat
      modprobe loop
      mkdir -p /run/glim
      attempt=0
      while [ "$attempt" -lt 30 ]; do
        attempt=$((attempt + 1))
        for device in $(blkid -t TYPE=vfat -o device); do
          if mount -t vfat -o ro "$device" /run/glim; then
            if [ -f "/run/glim$isofile" ]; then
              loopdev=$(losetup --find --show --read-only "/run/glim$isofile")
              echo "GLIM: attached $isofile from $device as $loopdev"
              udevadm trigger --action=change "/sys/class/block/''${loopdev##*/}"
              udevadm settle
              exit 0
            fi
            umount /run/glim
          fi
        done
        sleep 1
      done
      echo "GLIM: could not find $isofile on a FAT32 volume" >&2
      exit 1
    '';
  };

  networking.hostName = "nixos-recovery";
  networking.networkmanager.enable = true;

  boot.zfs.forceImportRoot = false;

  services.openssh.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.etc."nixos-recovery/source".source = repoSource;

  environment.systemPackages = with pkgs; [
    btrfs-progs
    cryptsetup
    dosfstools
    e2fsprogs
    efibootmgr
    git
    gptfdisk
    ntfs3g
    os-prober
    parted
    pciutils
    rsync
    usbutils
    util-linux
    vim
    (callPackage ../scripts/nixos-recovery-install.nix { })
  ];

  programs.git.enable = true;

  users.users.nixos = {
    extraGroups = [ "networkmanager" "wheel" ];
  };

  system.stateVersion = "25.11";
}
