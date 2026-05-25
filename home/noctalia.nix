{ config, lib, pkgs, inputs, ... }:

let
  wallpaperPath = "${config.home.homeDirectory}/.config/wallpapers/rocket-expedition.png";
  wallpaperCache = pkgs.writeText "noctalia-wallpapers.json" (builtins.toJSON {
    defaultWallpaper = wallpaperPath;
    usedRandomWallpapers = {};
    wallpapers =
      builtins.listToAttrs (map (name: {
        inherit name;
        value = {
          dark = wallpaperPath;
          light = wallpaperPath;
        };
      }) [
        "eDP-1"
        "DP-1"
        "DP-8"
        "DP-9"
        "DVI-I-1"
        "DVI-I-2"
      ]);
  });
in
{

  home.file.".config/wallpapers/rocket-expedition.png".source =
    ../assets/wallpapers/rocket-expedition.png;

  home.activation.noctaliaWallpaperCache = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.cache/noctalia"
    install -m 0644 ${wallpaperCache} "$HOME/.cache/noctalia/wallpapers.json"
  '';

  imports = [
    inputs.noctalia.homeModules.default
  ];

  programs.noctalia-shell = {
    enable = true;

    settings = {
      wallpaper = {
        enabled = true;
        directory = "${config.home.homeDirectory}/.config/wallpapers";
        fillMode = "crop";
      };
      bar = {
        position = "top";
        density = "default";

        widgets = {
          left = [
            {
              id = "ControlCenter";
              useDistroLogo = true;
            }

            {
              id = "SystemMonitor";

              compactMode = false;
              useMonospaceFont = true;
              usePadding = true;

              showCpuTemp = true;
              showCpuUsage = true;

              showMemoryUsage = true;
              showMemoryAsPercent = true;

              diskPath = "/";
              showDiskUsage = true;
              showDiskAvailable = true;
              showDiskUsageAsPercent = true;

              showCpuCores = false;
              showCpuFreq = false;
              showGpuTemp = false;
              showLoadAverage = false;
              showSwapUsage = false;
              showNetworkStats = false;

              iconColor = "none";
              textColor = "none";
            }
          ];

          center = [
            {
              id = "Workspace";
              hideUnoccupied = false;
              labelMode = "none";
            }
          ];

          right = [
            {
              id = "Network";
            }
            {
              id = "Battery";
              warningThreshold = 30;
            }
            {
              id = "Clock";
              formatHorizontal = "h:mm A";
              useMonospacedFont = true;
            }
          ];
        };
      };
    };
  };
}
