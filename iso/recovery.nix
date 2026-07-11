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

  image.fileName = lib.mkDefault "nixos-recovery-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}.iso";

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
