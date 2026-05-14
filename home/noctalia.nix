{ config, pkgs, inputs, ... }:

{
  imports = [
    inputs.noctalia.homeModules.default
  ];

  programs.noctalia-shell = {
    enable = true;

    settings = {
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
              formatHorizontal = "HH:mm";
              useMonospacedFont = true;
            }
          ];
        };
      };
    };
  };
}
