{ config, pkgs, inputs, ... }:

{

  home.file.".config/wallpapers/traffic-blur.jpg".source = 
    ../assets/wallpapers/traffic-blur.jpg;

  imports = [
    inputs.noctalia.homeModules.default
  ];

  programs.noctalia-shell = {
    enable = true;

    settings = {
      wallpaper = {
        enable = true;
        image = "${config.home.homeDirectory}/.config/wallpapers/traffic-blur.jpg";
        fillMode = "cover";
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
