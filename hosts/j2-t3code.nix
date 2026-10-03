{ config, lib, pkgs, username, ... }:
let
  caddy = pkgs.caddy.withPlugins {
    plugins = [ "github.com/caddy-dns/porkbun@v0.3.1" ];
    hash = "sha256-iFuoa6k2r3jUPazHHujhB4bBq3Fz0Mv0Tjsr+gxMYQQ=";
  };
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
    exec ${lib.getExe caddy} "$@"
  '';
in {
  users.users.${username}.linger = true;

  services.caddy = {
    enable = true;
    package = caddy;
    openFirewall = false;
    enableReload = false;
    environmentFile = "/etc/caddy/porkbun.env";
    globalConfig = ''
      auto_https disable_redirects
      default_bind {$CADDY_BIND_ADDRESSES}
    '';
    virtualHosts."j2t3c.d.salehh.xyz".extraConfig = ''
      bind {$CADDY_BIND_ADDRESSES}
      tls {
        dns porkbun {
          api_key {env.PORKBUN_API_KEY}
          api_secret_key {env.PORKBUN_API_SECRET_KEY}
        }
      }
      reverse_proxy 127.0.0.1:3773
    '';
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
