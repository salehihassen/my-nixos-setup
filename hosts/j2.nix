{ pkgs, ... }:
# Unique setup for j2 laptop
{
  # Networking
  networking.hostName = "j2";

  # BOOT , TODO migrate to separate module ====================================

  # Default, trying an alternative
  # Use the systemd-boot EFI boot loader.
  # boot.loader.systemd-boot.enable = true;
  # boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.luks.devices = {
    cryptnix = {
      device = "/dev/disk/by-uuid/e8c65ac8-b574-4bce-904a-4d6794c0b4c8";
      allowDiscards = true;
    };
    cryptnixswap = {
      device = "/dev/disk/by-uuid/040d1566-b5fb-4a6c-8b7d-21a64b56faba";
      allowDiscards = true;
    };
  };

  boot.resumeDevice = "/dev/mapper/cryptnixswap";

  boot.loader.systemd-boot.enable = false;

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";
    useOSProber = true;
    configurationLimit = 10;
  };

  boot.loader.efi = {
    canTouchEfiVariables = true;
    efiSysMountPoint = "/boot/efi";
  };

  # Extra boot entry for my PopOS partition
  boot.loader.grub.extraEntries = ''
    menuentry "Pop!_OS current" {
      insmod part_gpt
      insmod fat
      search --no-floppy --set=esp --file /EFI/Pop_OS-312e170d-932b-4e52-bbae-8564c41d00f9/vmlinuz.efi
      linux ($esp)/EFI/Pop_OS-312e170d-932b-4e52-bbae-8564c41d00f9/vmlinuz.efi
      root=UUID=312e170d-932b-4e52-bbae-8564c41d00f9 ro quiet loglevel=0
      systemd.show_status=false splash
      initrd ($esp)/EFI/Pop_OS-312e170d-932b-4e52-bbae-8564c41d00f9/initrd.img
    }
  '';

  # Enable printing service
  services.printing.enable = true;

  hardware.graphics.enable = true;

  services.xserver.videoDrivers = [ "displaylink" ];

  # Allow unfree drivers as needed
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (pkgs.lib.getName pkg) [
      "displaylink" # for docking station
      "evdi"
    ];
}
