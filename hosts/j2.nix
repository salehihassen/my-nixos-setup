{ lib, pkgs, ... }:
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
    useOSProber = lib.mkForce false;
    configurationLimit = 10;
  };

  boot.loader.efi = {
    canTouchEfiVariables = true;
    efiSysMountPoint = "/boot/efi";
  };

  # Pop!_OS maintains its own systemd-boot entries on the ESP. Chainload that
  # known-good boot manager instead of trying to boot Pop kernels from GRUB.
  boot.loader.grub.extraEntries = lib.mkForce ''
    menuentry "Pop!_OS" {
      insmod part_gpt
      insmod fat
      search --no-floppy --set=esp --file /EFI/systemd/systemd-bootx64.efi
      chainloader ($esp)/EFI/systemd/systemd-bootx64.efi
    }

    menuentry "Windows Boot Manager" {
      insmod part_gpt
      insmod fat
      search --no-floppy --set=esp --file /EFI/Microsoft/Boot/bootmgfw.efi
      chainloader ($esp)/EFI/Microsoft/Boot/bootmgfw.efi
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
