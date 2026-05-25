{ config, inputs, ... }:

{

  home.file.".config/wallpapers" = {
    source = ../assets/wallpapers;
    recursive = true;
  };

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
