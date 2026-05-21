# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).


{ config, lib, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Allow unfree as needed
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "displaylink"
    "evdi"
  ];


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
      search --no-floppy --set=esp --file /EFI/Pop_OS-312e170d-932b-4e52-bbae-8564c41d00f9/vmlinuz.efi
      chainloader ($esp)/EFI/Pop_OS-312e170d-932b-4e52-bbae-8564c41d00f9/vmlinuz.efi initrd=\EFI\Pop_OS-312e170d-932b-4e52-bbae-8564c41d00f9\initrd.img root=UUID=312e170d-932b-4e52-bbae-8564c41d00f9 ro quiet loglevel=0 systemd.show_status=false splash
    }

    menuentry "Pop!_OS previous kernel" {
      search --no-floppy --set=esp --file /EFI/Pop_OS-312e170d-932b-4e52-bbae-8564c41d00f9/vmlinuz-previous.efi
      chainloader ($esp)/EFI/Pop_OS-312e170d-932b-4e52-bbae-8564c41d00f9/vmlinuz-previous.efi initrd=\EFI\Pop_OS-312e170d-932b-4e52-bbae-8564c41d00f9\initrd.img-previous root=UUID=312e170d-932b-4e52-bbae-8564c41d00f9 ro quiet loglevel=0 systemd.show_status=false splash
    }
  '';

  boot.supportedFilesystems = [ "btrfs" ];

  services.fstrim.enable = true;

  # NETWORKING =============================================================

  # networking.hostName = "nixos"; # Define your hostname.
  # Configure network connections interactively with nmcli or nmtui.
  hardware.bluetooth.enable = true;
  networking.networkmanager.enable = true;
  networking.hostName = "j2";

  services.openssh = {
    enable = true;
    ports = [ 22 ];

    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = true;
    };
  };

  #networking.firewall = {
  #  enable = true;
  #  allowedTCPPorts = [ 22 ];
  #};
  security.polkit.enable = true;
  services.tailscale.enable = true;


  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  # POWER =====================================================
  services.power-profiles-daemon.enable = true;
  powerManagement.enable = true;
  services.upower.enable = true;

  # DISPLAY / AUDIO / APPS / LOGIN  =================
  # Enable the X11 windowing system.
  # services.xserver.enable = true;

  # Niri tiling compositor
  programs.niri.enable = true;
  # Wayland first login manager
  services.greetd.enable = true;
  # Graphical greetd greeter
  programs.regreet.enable = true;
  # Displaylink video driver
  services.xserver.videoDrivers = [ "displaylink" "modesetting" ];
  systemd.services.dlm.wantedBy = [ "multi-user.target" ];

  environment.systemPackages = with pkgs; [

    # Niri desktop basics
    niri
    xwayland-satellite
    fuzzel
    swaybg

    # Maybe will remove for niri desktop soon
    mako
    waybar

    # Docking and external devices
    displaylink

    # Termincal and clipboard screenshot basics
    alacritty
    wl-clipboard
    grim
    slurp
    wezterm
    ghostty

    # Audio/brightness/control helpers
    pamixer
    pavucontrol
    brightnessctl
    playerctl

    # File manager and tray/network tools
    nautilus
    networkmanagerapplet

    # Auth / priv prompts for GUI apps
    polkit
    kdePackages.polkit-kde-agent-1
    networkmanagerapplet

    # Lock screen (not login manager)
    swaylock

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

    # Virtualization
    inputs.compose2nix.packages.x86_64-linux.default

    # Dev
    uv

    # CLI tools
    git
    gh
    vim
    wget
    curl
    unzip
    tmux
    ripgrep
    imagemagick


    # Development
    pnpm

    # Networking
    tailscale
  ];

  # Enable AppImages
  programs.appimage.enable = true;
  programs.appimage.binfmt = true;

  # Enable Docker
  virtualisation.docker = {
    enable = true;
    # Set up resource limits
    daemon.settings = {
      experimental = true;
      default-address-pools = [
        {
          base = "172.30.0.0/16";
          size = 24;
        }
      ];
    };
    storageDriver = "btrfs";
  };

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

  programs.git.enable = true;

  # MISC =========================================

  # Configure keymap in X11
  # services.xserver.xkb.layout = "us";
  # services.xserver.xkb.options = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # EST Timezone
  time.timeZone = "America/New_York";
  # Keep Linux using UTC hardware clock.
  time.hardwareClockInLocalTime = false;
  # Usually enabled by default, but explicit is fine.
  services.timesyncd.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;

  # Create a NixOS config group, group is allowed to edit nixos configs
  users.groups.nixcfg = {};
  systemd.tmpfiles.rules = [
    "d /etc/nixos 2775 root nixcfg -"
  ];

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.saleh = {
    isNormalUser = true;
    extraGroups = [
      "nixcfg" # Enable modifying nixos configs
      "wheel" # Enable 'sudo' for the user
      "networkmanager" # Network mgmt
    ]; # Enable ‘sudo’ for the user.
    packages = with pkgs; [
      tree
    ];
  };

  programs.nix-ld = {
    enable = true;

    libraries = with pkgs; [
      stdenv.cc.cc
      zlib
      openssl
    ];
  };

  # programs.firefox.enable = true;

  # List packages installed in system profile.
  # You can use https://search.nixos.org/ to find more packages (and options).
  # environment.systemPackages = with pkgs; [
  #   vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #   wget
  # ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "25.11"; # Did you read the comment?

}

