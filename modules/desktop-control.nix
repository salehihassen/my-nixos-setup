# Opt-in, approved AI desktop control (computer use) for NixOS hosts.
#
# Not imported anywhere by default. A host turns it on with:
#
#   imports = [ ../modules/desktop-control.nix ];
#   services.desktop-control.enable = true;
#
# The design: ydotoold's socket is group-locked to the dedicated "ydotool"
# group with NO user members. The only two ways to inject input are:
#
#   1. The desktop-control service - a system service running as the desktop
#      user with SupplementaryGroups=ydotool, so only it (not the user's
#      shell, browser, or npm scripts) can inject arbitrary input. Every
#      action requires an on-screen fuzzel APPROVE prompt.
#   2. capture-keys - a setgid helper restricted to the two tab-cycling key
#      chords Ctrl+Tab / Ctrl+Shift+Tab, for screenshot captures of every
#      browser tab. It can switch tabs, nothing more.
#
# pyOS heads: Home Manager (home/desktop-control.nix) holds the portable
# client pieces; this module is the NixOS-only privilege boundary.
{
  config,
  lib,
  pkgs,
  username ? "saleh",
  dotfilesRoot ? "/etc/nixos",
  ...
}:

let
  cfg = config.services.desktop-control;

  crosshair = pkgs.stdenv.mkDerivation {
    pname = "desktop-control-crosshair";
    version = "1";
    src = ../scripts/desktop-control/crosshair.c;
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [
      pkgs.gtk4
      pkgs.gtk4-layer-shell
    ];
    buildPhase = ''
      $CC "$src" -o desktop-control-crosshair $(pkg-config --cflags --libs gtk4 gtk4-layer-shell-0)
    '';
    installPhase = ''
      install -Dm755 desktop-control-crosshair "$out/bin/desktop-control-crosshair"
    '';
  };

  pointer = pkgs.stdenv.mkDerivation {
    pname = "desktop-control-pointer";
    version = "1";
    src = ../scripts/desktop-control/pointer.c;
    dontUnpack = true;
    nativeBuildInputs = [
      pkgs.pkg-config
      pkgs.wayland-scanner
    ];
    buildInputs = [ pkgs.wayland ];
    buildPhase = ''
      protocol=${pkgs.wlr-protocols}/share/wlr-protocols/unstable/wlr-virtual-pointer-unstable-v1.xml
      wayland-scanner client-header "$protocol" wlr-virtual-pointer-unstable-v1-client-protocol.h
      wayland-scanner private-code "$protocol" pointer-protocol.c
      $CC -I. "$src" pointer-protocol.c -o desktop-control-pointer $(pkg-config --cflags --libs wayland-client)
    '';
    installPhase = ''
      install -Dm755 desktop-control-pointer "$out/bin/desktop-control-pointer"
    '';
  };

  # The system service runs outside the graphical session, so the Niri
  # socket path is not in its environment. Discover it at start time and
  # derive WAYLAND_DISPLAY from the socket name (niri.<display>.<pid>.sock).
  serviceLauncher = pkgs.writeShellApplication {
    name = "desktop-control-service";
    text = ''
      script=${lib.escapeShellArg "${dotfilesRoot}/scripts/desktop-control/service.mjs"}
      if [[ ! -r "$script" ]]; then
        printf 'Checkout script is missing: %s\nCheck dotfilesRoot.\n' "$script" >&2
        exit 1
      fi
      runtime_dir="/run/user/${toString cfg.uid}"
      sock=""
      for candidate in "$runtime_dir"/niri.*.sock; do
        [[ -S "$candidate" ]] && { sock="$candidate"; break; }
      done
      if [[ -z "$sock" ]]; then
        printf 'No Niri socket in %s; start a graphical session first.\n' "$runtime_dir" >&2
        exit 1
      fi
      export NIRI_SOCKET="$sock"
      display="''${sock##*/}"
      display="''${display#niri.}"
      display="''${display%%.*}"
      export WAYLAND_DISPLAY="''${display:-wayland-1}"
      exec ${pkgs.nodejs_24}/bin/node "$script" "$@"
    '';
  };

  # Restricted tab-cycling helper. Bash would drop the effective group unless
  # invoked with -p, hence the non-standard shebang.
  captureKeys = pkgs.writeTextFile {
    name = "capture-keys";
    executable = true;
    destination = "/capture-keys";
    text = ''
      #!${pkgs.runtimeShell} -p
      set -eu
      export YDOTOOL_SOCKET=/run/ydotoold/socket
      case "''${1:-}" in
        tab-next) exec ${pkgs.ydotool}/bin/ydotool key 29:1 15:1 15:0 29:0 ;;
        tab-prev) exec ${pkgs.ydotool}/bin/ydotool key 29:1 42:1 15:1 15:0 42:0 29:0 ;;
        *)
          echo "usage: capture-keys tab-next|tab-prev" >&2
          exit 2
          ;;
      esac
    '';
  };
in
{
  options.services.desktop-control = {
    enable = lib.mkEnableOption "approved AI desktop control via ydotool";

    user = lib.mkOption {
      type = lib.types.str;
      default = username;
      description = ''
        Desktop user whose graphical session receives approval prompts and
        runs the service. Does not gain ydotool group membership.
      '';
    };

    uid = lib.mkOption {
      type = lib.types.int;
      default = 1000; # single-user NixOS default; adjust per host
      description = ''
        UID of the desktop user, used for /run/user/<uid> paths. On
        multi-user machines set this to the target user's real UID (`id -u`).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.ydotool.enable = true;
    # Dedicated group with no members; only the service (and the restricted
    # capture-keys wrapper) get ydotool access.
    programs.ydotool.group = "ydotool";

    security.polkit.extraConfig = ''
      // The approved AI control service may be started and stopped by the
      // desktop user without a password. Input actions still require an
      // on-screen fuzzel APPROVE prompt from the service itself.
      polkit.addRule(function(action, subject) {
        if (action.id === "org.freedesktop.systemd1.manage-units" &&
            action.lookup("unit") === "desktop-control.service" &&
            subject.user === "${cfg.user}") {
          return polkit.Result.YES;
        }
      });
    '';

    security.wrappers.capture-keys = {
      source = "${captureKeys}/capture-keys";
      setgid = true;
      owner = "root";
      group = config.programs.ydotool.group;
      permissions = "u+rx,g+x,o+x";
    };

    systemd.services.desktop-control = {
      description = "Approved local desktop controls for AI harnesses";
      # Started explicitly (systemctl start desktop-control); the polkit rule
      # above makes that passwordless for the desktop user.
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        SupplementaryGroups = [ config.programs.ydotool.group ];
        ExecStart = lib.getExe serviceLauncher;
        Restart = "no";
        # A stop during a drag or chord must not leave the virtual device held down.
        ExecStopPost = [
          "-${pkgs.ydotool}/bin/ydotool click 0x80 0x81 0x82"
          "-${pkgs.ydotool}/bin/ydotool key 29:0 42:0 56:0 125:0"
        ];
      };
      environment = {
        XDG_RUNTIME_DIR = "/run/user/${toString cfg.uid}";
        DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/${toString cfg.uid}/bus";
        YDOTOOL_SOCKET = "/run/ydotoold/socket";
        NIRI_BIN = "${pkgs.niri}/bin/niri";
        GRIM_BIN = "${pkgs.grim}/bin/grim";
        YDOTOOL_BIN = "${pkgs.ydotool}/bin/ydotool";
        FUZZEL_BIN = "${pkgs.fuzzel}/bin/fuzzel";
        CROSSHAIR_BIN = "${crosshair}/bin/desktop-control-crosshair";
        POINTER_BIN = "${pointer}/bin/desktop-control-pointer";
        WLRCTL_BIN = "${pkgs.wlrctl}/bin/wlrctl";
        NOTIFY_BIN = "${pkgs.libnotify}/bin/notify-send";
      };
    };
  };
}
