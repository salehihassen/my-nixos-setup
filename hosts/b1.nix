{ lib, ... }:

{
  # Future Proxmox VM host. Add ./b1-hardware.nix after generating it inside b1.
  networking.hostName = "b1";

  # Evaluation placeholders only. Replace these with generated VM hardware before switching b1.
  boot.loader.grub.enable = false;
  fileSystems."/" = lib.mkDefault {
    device = "none";
    fsType = "tmpfs";
  };
}
