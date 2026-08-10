{
  pkgs,
  username ? "saleh",
  ...
}:

let
  guiBusName = "proton.vpn.app.gtk";

  protonvpn-toggle = pkgs.writeShellApplication {
    name = "protonvpn-toggle";
    runtimeInputs = with pkgs; [
      coreutils
      glib
      gnugrep
      libnotify
      proton-vpn-cli
      util-linux
    ];
    text = ''
      lock_file="''${XDG_RUNTIME_DIR:?}/protonvpn-client.lock"
      exec 9>"$lock_file"

      if ! flock --nonblock 9; then
        notify-send --app-name="Proton VPN" "VPN change already in progress"
        exit 0
      fi

      if ! gui_owner="$(
        gdbus call \
          --session \
          --dest org.freedesktop.DBus \
          --object-path /org/freedesktop/DBus \
          --method org.freedesktop.DBus.NameHasOwner \
          ${guiBusName} 2>&1
      )"; then
        notify-send --urgency=critical --app-name="Proton VPN" \
          "Could not check Proton VPN GUI state" "$gui_owner"
        exit 1
      fi

      if [[ "$gui_owner" == "(true,)" ]]; then
        notify-send --app-name="Proton VPN" \
          "CLI toggle refused" \
          "Close the Proton VPN GUI before using Mod+Ctrl+V."
        exit 0
      fi

      if ! status="$(protonvpn status 2>&1)"; then
        notify-send --urgency=critical --app-name="Proton VPN" \
          "Could not read VPN status" "$status"
        exit 1
      fi

      if grep --quiet '^Status: Connected' <<<"$status"; then
        if output="$(protonvpn disconnect 2>&1)"; then
          notify-send --app-name="Proton VPN" "VPN disconnected"
        else
          notify-send --urgency=critical --app-name="Proton VPN" \
            "VPN disconnect failed" "$output"
          exit 1
        fi
      elif grep --quiet '^Status: Disconnected' <<<"$status"; then
        notify-send --app-name="Proton VPN" "Connecting VPN…"

        if output="$(protonvpn connect 2>&1)"; then
          details="$(protonvpn status 2>&1 | head --lines=5)"
          notify-send --app-name="Proton VPN" "VPN connected" "$details"
        else
          notify-send --urgency=critical --app-name="Proton VPN" \
            "VPN connection failed" \
            "Run 'protonvpn signin USERNAME' in a terminal first.

$output"
          exit 1
        fi
      else
        notify-send --app-name="Proton VPN" \
          "VPN is busy" "$status"
      fi
    '';
  };

  protonvpn-gui-safe = pkgs.writeShellApplication {
    name = "protonvpn-gui-safe";
    runtimeInputs = with pkgs; [
      coreutils
      glib
      libnotify
      proton-vpn
      proton-vpn-cli
      util-linux
    ];
    text = ''
      lock_file="''${XDG_RUNTIME_DIR:?}/protonvpn-client.lock"
      exec 9>"$lock_file"

      if ! flock --nonblock 9; then
        notify-send --app-name="Proton VPN" "VPN change already in progress"
        exit 0
      fi

      if ! gui_owner="$(
        gdbus call \
          --session \
          --dest org.freedesktop.DBus \
          --object-path /org/freedesktop/DBus \
          --method org.freedesktop.DBus.NameHasOwner \
          ${guiBusName} 2>&1
      )"; then
        notify-send --urgency=critical --app-name="Proton VPN" \
          "Could not check Proton VPN GUI state" "$gui_owner"
        exit 1
      fi

      if [[ "$gui_owner" == "(true,)" ]]; then
        exec 9>&-
        exec protonvpn-app
      fi

      if ! status="$(protonvpn status 2>&1)"; then
        notify-send --urgency=critical --app-name="Proton VPN" \
          "Could not read VPN status" "$status"
        exit 1
      fi

      if grep --quiet '^Status: Disconnected' <<<"$status"; then
        (
          exec 9>&-
          exec protonvpn-app >/dev/null 2>&1
        ) &
        gui_pid=$!

        for _ in $(seq 1 50); do
          gui_owner="$(
            gdbus call \
              --session \
              --dest org.freedesktop.DBus \
              --object-path /org/freedesktop/DBus \
              --method org.freedesktop.DBus.NameHasOwner \
              ${guiBusName} 2>/dev/null
          )"

          if [[ "$gui_owner" == "(true,)" ]]; then
            exec 9>&-
            exit 0
          fi

          if ! kill -0 "$gui_pid" 2>/dev/null; then
            wait "$gui_pid" || true
            notify-send --urgency=critical --app-name="Proton VPN" \
              "Proton VPN GUI failed to start"
            exit 1
          fi

          sleep 0.1
        done

        notify-send --urgency=critical --app-name="Proton VPN" \
          "Proton VPN GUI startup timed out"
        exit 1
      fi

      notify-send --app-name="Proton VPN" \
        "GUI launch refused" \
        "The CLI VPN is active or changing state. Disconnect it with Mod+Ctrl+V first.

$status"
    '';
  };
in

{
  networking.networkmanager.plugins = with pkgs; [
    networkmanager-openvpn
  ];

  environment.systemPackages = with pkgs; [
    proton-vpn
    proton-vpn-cli
    protonvpn-gui-safe
    protonvpn-toggle
  ];

  home-manager.users.${username} = {
    xdg.desktopEntries."proton.vpn.app.gtk" = {
      name = "Proton VPN";
      comment = "Proton VPN GUI client";
      exec = "${protonvpn-gui-safe}/bin/protonvpn-gui-safe";
      icon = "proton-vpn-logo";
      terminal = false;
      categories = [ "Network" ];
      settings.StartupWMClass = ".protonvpn-app-wrapped";
    };
  };
}
