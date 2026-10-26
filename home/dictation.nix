{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.dictation;
  runtime = "%t/dictation";
  settings = pkgs.writeText "dictation.json" (
    builtins.toJSON {
      inherit (cfg)
        idleTimeout
        recordingLimit
        polishTimeout
        niriIntegration
        modelPath
        ;
      polishModel = cfg.polishModel;
      ollamaUrl = "http://127.0.0.1:${toString cfg.ollamaPort}";
      voxtype = lib.getExe cfg.package;
      niri = if cfg.niriIntegration then lib.getExe pkgs.niri else "";
      wtype = lib.getExe pkgs.wtype;
      wlCopy = "${pkgs.wl-clipboard}/bin/wl-copy";
      notify = "${pkgs.libnotify}/bin/notify-send";
      systemctl = "${pkgs.systemd}/bin/systemctl";
      curl = lib.getExe pkgs.curl;
      whisperUrl = cfg.modelUrl;
      whisperSha256 = cfg.modelSha256;
    }
  );
  controller = pkgs.writeShellApplication {
    name = "dictation";
    text = ''
      export DICTATION_CONFIG=${settings}
      exec ${pkgs.python3}/bin/python3 ${../scripts/dictation.py} "$@"
    '';
  };
  idleTimer = component: {
    Unit.Description = "Release idle dictation ${component}";
    Timer = {
      OnActiveSec = "${toString cfg.idleTimeout}s";
      AccuracySec = "1s";
      Unit = "dictation-${component}-idle.service";
    };
  };
  idleService = component: {
    Unit.Description = "Release idle dictation ${component}";
    Service = {
      Type = "oneshot";
      ExecStart = "${controller}/bin/dictation idle ${component}";
      UMask = "0077";
    };
  };
in
{
  options.programs.dictation = {
    enable = lib.mkEnableOption "on-demand local dictation";
    package = lib.mkPackageOption pkgs "voxtype" { };
    modelPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.dataHome}/voxtype/models/ggml-large-v3-turbo.bin";
      description = "Local Whisper model; downloaded explicitly with dictation setup.";
    };
    modelUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin";
    };
    modelSha256 = lib.mkOption {
      type = lib.types.str;
      default = "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69";
    };
    polishModel = lib.mkOption {
      type = lib.types.str;
      default = "llama3.2:3b";
    };
    ollamaPackage = lib.mkPackageOption pkgs "ollama" { };
    ollamaAcceleration = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          false
          "vulkan"
          "rocm"
          "cuda"
        ]
      );
      default = false;
    };
    ollamaPort = lib.mkOption {
      type = lib.types.port;
      default = 11435;
    };
    microphone = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = "ALSA capture device; default follows PipeWire's default microphone on NixOS.";
    };
    recordingLimit = lib.mkOption {
      type = lib.types.ints.positive;
      default = 300;
    };
    idleTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 60;
    };
    polishTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 45;
    };
    niriIntegration = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      controller
      pkgs.wtype
      pkgs.wl-clipboard
    ];
    # Also expose the controller when activating the NixOS-managed home
    # generation directly, before root installs its home.packages profile.
    home.file.".local/bin/dictation".source = "${controller}/bin/dictation";

    services.voxtype = {
      enable = true;
      package = cfg.package;
      loadModels = [ ];
      settings = {
        engine = "whisper";
        state_file = "auto";
        hotkey.enabled = false;
        audio = {
          device = cfg.microphone;
          sample_rate = 16000;
          max_duration_secs = cfg.recordingLimit;
        };
        whisper = {
          model = cfg.modelPath;
          language = "en";
          translate = false;
          on_demand_loading = false;
          gpu_isolation = false;
          threads = 8;
        };
        output = {
          mode = "file";
          fallback_to_clipboard = false;
          notification = {
            on_recording_start = false;
            on_recording_stop = false;
            on_transcription = false;
            on_no_speech = false;
          };
        };
        osd.enabled = false;
      };
    };
    systemd.user.services.voxtype = {
      Install.WantedBy = lib.mkForce [ ];
      Service = {
        ExecStart = lib.mkForce "${lib.getExe cfg.package} --quiet daemon";
        Restart = lib.mkForce "no";
        TimeoutStopSec = 5;
        UMask = "0077";
        StandardOutput = "null";
      };
    };

    # The upstream Home Manager Ollama unit is reserved for dictation. The
    # separate loopback port leaves the system/default Ollama endpoint alone.
    services.ollama = {
      enable = true;
      package = cfg.ollamaPackage;
      acceleration = cfg.ollamaAcceleration;
      host = "127.0.0.1";
      port = cfg.ollamaPort;
      environmentVariables = {
        OLLAMA_NO_CLOUD = "1";
        OLLAMA_KEEP_ALIVE = "-1";
        OLLAMA_NUM_PARALLEL = "1";
        OLLAMA_CONTEXT_LENGTH = "4096";
        OLLAMA_MODELS = "${config.home.homeDirectory}/.ollama/models";
      };
    };
    systemd.user.services.ollama = {
      Install.WantedBy = lib.mkForce [ ];
      Service = {
        UMask = "0077";
        TimeoutStopSec = 10;
      };
    };

    systemd.user.sockets.dictation = {
      Unit.Description = "On-demand local dictation control socket";
      Socket = {
        ListenStream = "${runtime}/control.sock";
        SocketMode = "0600";
        DirectoryMode = "0700";
        RemoveOnStop = true;
      };
    };
    systemd.user.services.dictation = {
      Unit = {
        Description = "On-demand local dictation controller";
        Requires = [ "dictation.socket" ];
        After = [ "dictation.socket" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${controller}/bin/dictation daemon";
        UMask = "0077";
        TimeoutStopSec = 15;
        # A controller crash must not leave a microphone or model running.
        ExecStopPost = "${pkgs.systemd}/bin/systemctl --user --no-block stop voxtype.service ollama.service dictation-voxtype-idle.timer dictation-ollama-idle.timer";
      };
    };
    systemd.user.timers.dictation-voxtype-idle = idleTimer "voxtype";
    systemd.user.timers.dictation-ollama-idle = idleTimer "ollama";
    systemd.user.services.dictation-voxtype-idle = idleService "voxtype";
    systemd.user.services.dictation-ollama-idle = idleService "ollama";

    xdg.configFile."niri/dictation.kdl" = lib.mkIf cfg.niriIntegration {
      text = ''
        binds {
          Super+Alt+D repeat=false hotkey-overlay-title="Dictation: polished" { spawn "${controller}/bin/dictation" "toggle" "polished"; }
          Super+Alt+Shift+D repeat=false hotkey-overlay-title="Dictation: faithful" { spawn "${controller}/bin/dictation" "toggle" "faithful"; }
          Super+Alt+Escape repeat=false hotkey-overlay-title="Cancel dictation" { spawn "${controller}/bin/dictation" "cancel"; }
        }
      '';
    };
  };
}
