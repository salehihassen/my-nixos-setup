{ lib, ... }:

{
  # Future Proxmox VM host. Add ./b1-hardware.nix after generating it inside b1.
  networking.hostName = "b1";

  # Password auth is intentional here: b1's VMs are reachable via public IP,
  # where key enrollment may not have happened yet. Physical devices
  # (j2 and the new-computer template) stay key-only and only expose sshd
  # on the Tailscale interface.
  services.openssh = {
    openFirewall = true;
    settings = {
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = true;
    };
  };

  # Evaluation placeholders only. Replace these with generated VM hardware before switching b1.
  boot.loader.grub.enable = false;
  fileSystems."/" = lib.mkDefault {
    device = "none";
    fsType = "tmpfs";
  };
}
