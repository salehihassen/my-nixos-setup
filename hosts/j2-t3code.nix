{ config, lib, pkgs, username, ... }:
let
  prepareAddresses = pkgs.writeShellApplication {
    name = "t3code-caddy-addresses";
    runtimeInputs = [ pkgs.tailscale pkgs.coreutils ];
    text = ''
      ipv4="$(tailscale ip -4)"
      ipv6="$(tailscale ip -6)"
      if [[ -z "$ipv4" || -z "$ipv6" ]]; then
        echo "Waiting for Tailscale addresses" >&2
        exit 75
      fi
      # No machine addresses or credentials are embedded in the Nix store.
      printf 'export CADDY_BIND_ADDRESSES="%s %s"\n' "$ipv4" "$ipv6" > /run/t3code-caddy/addresses.env
    '';
  };
  runCaddy = pkgs.writeShellScript "t3code-caddy-run" ''
    set -eu
    . /run/t3code-caddy/addresses.env
    exec ${lib.getExe config.services.caddy.package} "$@"
  '';
in {
  users.users.${username}.linger = true;

  security.acme = {
    acceptTerms = true;
    certs."j2t3c.d.salehh.xyz" = {
      dnsProvider = "porkbun";
      environmentFile = "/etc/caddy/porkbun.env";
    };
  };

  # Reuse the existing credentials file; Lego names the secret differently.
  systemd.services."acme-order-renew-j2t3c.d.salehh.xyz".script = lib.mkBefore ''
    export PORKBUN_SECRET_API_KEY="$PORKBUN_API_SECRET_KEY"
  '';

  services.caddy = {
    enable = true;
    openFirewall = false;
    enableReload = false;
    globalConfig = ''
      auto_https disable_redirects
      default_bind {$CADDY_BIND_ADDRESSES}
    '';
    virtualHosts."j2t3c.d.salehh.xyz" = {
      useACMEHost = "j2t3c.d.salehh.xyz";
      extraConfig = ''
        bind {$CADDY_BIND_ADDRESSES}
        reverse_proxy 127.0.0.1:3773
      '';
    };
    # Native Tailscale hostname and IP fallback. This intentionally serves HTTP
    # over WireGuard, without claiming Tailscale Serve's HTTPS listener.
    extraConfig = ''
      http://:3773 {
        bind {$CADDY_BIND_ADDRESSES}
        reverse_proxy 127.0.0.1:3773
      }
    '';
  };

  systemd.services.caddy = {
    wants = [ "tailscaled.service" ];
    after = [ "tailscaled.service" ];
    startLimitIntervalSec = lib.mkForce 0;
    serviceConfig = {
      RuntimeDirectory = "t3code-caddy";
      RuntimeDirectoryMode = "0700";
      ExecStartPre = [ "${prepareAddresses}/bin/t3code-caddy-addresses" ];
      ExecStart = lib.mkForce [ "" "${runCaddy} run --config /etc/caddy/caddy_config --adapter caddyfile" ];
      RestartPreventExitStatus = lib.mkForce "";
    };
  };
}
