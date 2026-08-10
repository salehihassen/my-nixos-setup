{ config, pkgs, inputs, ... }:
# Unique setup for j2 laptop
{
  imports = [
    ./j2-hardware.nix
    ../home/protonvpn-toggle.nix
  ];

  # Networking
  networking.hostName = "j2";

  services.tailscale.enable = true;
  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;
    trustedInterfaces = [ config.services.tailscale.interfaceName ];
    allowedUDPPorts = [ config.services.tailscale.port ];
    checkReversePath = false;
  };

  # Force tailscaled to use nftables and avoid iptables-compat translation issues.
  systemd.services.tailscaled.serviceConfig.Environment = [
    "TS_DEBUG_FIREWALL_MODE=nftables"
  ];

  /*
  systemd.services.tailscaled-autoconnect = {
    after = [ "tailscaled.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig.Type = "oneshot";

    script = ''
      ${pkgs.tailscale}/bin/tailscale set --accept-dns=false
    '';
  };
  */

  hardware.bluetooth.enable = true;

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

  boot.supportedFilesystems = [ "btrfs" "vfat" "exfat" "ntfs" ];

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

  services.udisks2.enable = true;
  services.gvfs.enable = true;
  services.fstrim.enable = true;

  # POWER =====================================================
  services.power-profiles-daemon.enable = true;
  powerManagement.enable = true;
  services.upower.enable = true;

  # DISPLAY / AUDIO / APPS / LOGIN  =================
  # Niri tiling compositor
  programs.niri.enable = true;
  # Wayland first login manager
  services.greetd.enable = true;
  # Graphical greetd greeter
  programs.regreet = {
    enable = true;
    cageArgs = [ "-s" "-d" "-m" "extend" ];
  };

  hardware.graphics.enable = true;

  services.xserver.videoDrivers = [ "displaylink" "modesetting" ];
  systemd.services.dlm.wantedBy = [ "multi-user.target" ];

  security.polkit.enable = true;

  # Enable AppImages
  programs.appimage.enable = true;
  programs.appimage.binfmt = true;

  # Helps Chromium/Electron apps prefer Wayland
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };

  # Portals help file pickers and sandboxed apps
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
    ];
  };

  # Audio
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
  };

  virtualisation.docker.storageDriver = "btrfs";

  # Allow unfree drivers as needed
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (pkgs.lib.getName pkg) [
      "displaylink" # for docking station
      "evdi"
      "steam-unwrapped"
      "claude-code"
      "discord"
    ];

  # AI
  environment.systemPackages = with pkgs; [
    # Networking
    tailscale

    # Niri desktop basics
    niri
    xwayland-satellite
    fuzzel
    swaybg

    # Docking and external devices
    displaylink

    # Terminal and clipboard screenshot basics
    alacritty
    wl-clipboard
    grim
    slurp
    wezterm
    ghostty

    # Audio/brightness/control helpers
    pamixer
    pavucontrol

    # File manager and tray/network tools
    nautilus
    networkmanagerapplet
    wireguard-tools

    # Auth / priv prompts for GUI apps
    polkit
    kdePackages.polkit-kde-agent-1

    # Themes / icons so GTK apps do not look broken
    adwaita-icon-theme
    gnome-themes-extra

    # Portals
    xdg-desktop-portal
    xdg-desktop-portal-gtk

    # Browsers
    chromium

    # Boot / firmware tools
    efibootmgr
    os-prober
    gparted

    ollama-vulkan

    # Comms
    discord
  ];
}
