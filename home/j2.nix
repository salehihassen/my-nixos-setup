{ pkgs, ... }:

{
  imports = [
    ./t3code.nix
    ./dictation.nix
  ];

  programs.dictation = {
    enable = true;
    package = pkgs.voxtype-vulkan;
    niriIntegration = true;
  };

  programs.snapshot-work.sourceMode = "checkout";
  home.sessionVariables.YDOTOOL_SOCKET = "/run/ydotoold/socket";

  # Preserve J2's local associations when Home Manager takes ownership.
  xdg.mimeApps = {
    associations.added = {
      "video/mp4" = "chromium-browser.desktop";
      "application/vnd.openxmlformats-officedocument.presentationml.presentation" =
        "chromium-browser.desktop";
      "x-scheme-handler/http" = "zen-beta.desktop";
      "x-scheme-handler/https" = "zen-beta.desktop";
      "x-scheme-handler/chrome" = "zen-beta.desktop";
      "text/html" = "zen-beta.desktop";
      "application/x-extension-htm" = "zen-beta.desktop";
      "application/x-extension-html" = "zen-beta.desktop";
      "application/x-extension-shtml" = "zen-beta.desktop";
      "application/xhtml+xml" = "zen-beta.desktop";
      "application/x-extension-xhtml" = "zen-beta.desktop";
      "application/x-extension-xht" = "zen-beta.desktop";
    };
    defaultApplications = {
      "x-scheme-handler/chrome" = "zen-beta.desktop";
      "application/x-extension-htm" = "zen-beta.desktop";
      "application/x-extension-html" = "zen-beta.desktop";
      "application/x-extension-shtml" = "zen-beta.desktop";
      "application/xhtml+xml" = "zen-beta.desktop";
      "application/x-extension-xhtml" = "zen-beta.desktop";
      "application/x-extension-xht" = "zen-beta.desktop";
      "x-scheme-handler/claude-cli" = "claude-code-url-handler.desktop";
      "x-scheme-handler/web+nextcloudreddit" = "chromium-browser.desktop";
      "x-scheme-handler/webcal" = "chromium-browser.desktop";
    };
  };

  home.packages = with pkgs; [
    home-assistant-cli
    huggingface-cli

    # Browsers and communication
    discord
    zoom-us

    # Backups
    borgbackup

    # Oracle cloud cli
    oci-cli

    (stdenvNoCC.mkDerivation (finalAttrs: {
      pname = "nebius-cli";
      version = "0.12.305";
      src = fetchurl {
        url = "https://artifacts.nebius.cloud/cli/release/${finalAttrs.version}/linux/x86_64/nebius";
        hash = "sha256-akJ7+YcJlOWpnkKUOV6ZPUxiqfRJrwnWJDVuS5beNWI=";
      };
      dontUnpack = true;
      installPhase = ''
        runHook preInstall
        install -Dm755 "$src" "$out/bin/nebius"
        runHook postInstall
      '';
      meta.mainProgram = "nebius";
    }))

    # Permanently redact text and images from PDFs before sharing.
    censor

    # Games
    (steam.override {
      # Older LWJGL versions query display modes through this command.
      extraPkgs = pkgs: [ pkgs.xrandr ];
      # Downloaded Java and Minecraft natives need these at runtime.
      extraLibraries = pkgs: with pkgs; [
        libxtst
        libxxf86vm
        alsa-lib
        libpulseaudio
      ];
    }).run

    # Keyboard firmware
    qmk
    dos2unix

    # Terminals and desktop helpers
    alacritty
    wezterm
    swaybg
    pamixer
    pavucontrol
    gimp
    networkmanagerapplet
  ];
}
