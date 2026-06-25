{ config, inputs, ... }:

{

  home.file.".config/wallpapers" = {
    source = ../assets/wallpapers;
    recursive = true;
  };

  imports = [
    inputs.noctalia.homeModules.default
  ];

  programs.noctalia = {
    enable = true;
    systemd.enable = true;

    settings = {
      wallpaper = {
        enabled = true;
        directory = "${config.home.homeDirectory}/.config/wallpapers";
        fill_mode = "crop";
      };
      bar = {
        main = {
          position = "top";
          start = [
            "control-center"
            "cpu"
            "temp"
            "ram"
            "disk"
          ];
          center = [
            "workspaces"
          ];
          end = [
            "network"
            "battery"
            "clock"
          ];
        };
      };
      battery = {
        warning_threshold = 30;
      };
      shell = {
        time_format = "{:%I:%M %p}";
      };
      widget = {
        cpu = {
          type = "sysmon";
          stat = "cpu_usage";
        };
        temp = {
          type = "sysmon";
          stat = "cpu_temp";
        };
        ram = {
          type = "sysmon";
          stat = "ram_used";
        };
        disk = {
          type = "sysmon";
          stat = "disk_pct";
        };
      };
    };
  };
}
