# T3 Code on J2

J2 runs the nightly source server from the independently pinned
`t3-code-nix` flake. Configure the channel, source/prebuilt variant, or package
override in `home/t3code.nix`. The desktop client is not installed.

## Connect

- Preferred: <https://j2t3c.d.salehh.xyz>
- Fallback: <http://j2.taile962f.ts.net:3773>
- IPv4 fallback: use `http://<address from tailscale ip -4>:3773`.

Caddy binds HTTPS and the HTTP fallback exclusively to J2's current Tailscale
IPv4/IPv6 addresses. HTTP fallback traffic is encrypted by Tailscale's tunnel.
The backend listens on `127.0.0.1:3773`. Porkbun A/AAAA records point the custom
hostname to J2's tailnet addresses; update them if the node is re-enrolled with
new addresses. No LAN/public firewall ports are opened.

For each client, mint a fresh one-time pairing link:

```sh
t3code-pair
# If custom DNS or certificate issuance is unavailable:
t3code-pair http://j2.taile962f.ts.net:3773
t3code-pair "http://$(tailscale ip -4):3773"
```

Open the printed link on a tailnet device or add it under T3 Code's
Connections/Add environment. The helper preserves the token and replaces only
the CLI's loopback origin. Pairing links are credentials; don't commit or log
them. Revoke clients through T3 Code's Connections settings.

Do not run `t3 pair --tailscale`, `t3 serve --tailscale-serve`, or enable
Tailscale Serve/Funnel: Caddy owns J2's tailnet HTTPS listener.

## Service and state

```sh
systemctl --user status t3code
journalctl --user -u t3code -n 50
systemctl --user restart t3code
systemctl status caddy
journalctl -u caddy -n 50
loginctl show-user saleh -p Linger
```

User lingering starts T3 Code before login and keeps it running after logout.
Existing sleep behavior is preserved: remote access stops during suspend or
while J2 is booted into Windows, and resumes after NixOS wakes/starts.

The persistent base directory is `~/.t3` (including `userdata` and authentication
state); the working directory is `/home/saleh`. The service uses existing Codex
from `~/.npm-global/bin` and packaged Claude, plus existing credentials in the
user's home. Authenticate expired providers interactively as Saleh.

Caddy reads Porkbun credentials from `/etc/caddy/porkbun.env`, owned by root
with mode 600. Machine addresses are discovered into
`/run/t3code-caddy/addresses.env` at each Caddy start. Neither is in Git or the
Nix store. Caddy certificates/state live in `/var/lib/caddy`.

For initial setup with credentials staged in `~/.local/share/t3code-provisioning/porkbun.env`, run:

```sh
sudo bash /etc/nixos/scripts/activate-t3code.sh
```

The helper installs the credentials, rebuilds and switches, then removes the staged credentials after success.

## Update or switch channel

Automatic application updates are disabled. The packaging flake tracks upstream
releases; updating its input leaves the system's nixpkgs pin unchanged.

```sh
cd /etc/nixos
nix flake update t3-code-nix
nixos-rebuild build --flake /etc/nixos#j2 --cores 4 --max-jobs 1
```

To switch channels or build variants, edit `channel`/`packageVariant` in
`home/t3code.nix` before building. Source builds also build a shared desktop
bundle and can take several minutes. Match remote client versions where
required by T3 Code.

After a successful build, wait for active agent work to finish, then back up
state with the service stopped before switching:

```sh
systemctl --user stop t3code
backup_dir="$HOME/.local/state/t3code-backups"
mkdir -p "$backup_dir"
chmod 700 "$backup_dir"
if ! (umask 077; tar -C "$HOME" -czf "$backup_dir/$(date +%Y%m%dT%H%M%S).tar.gz" .t3); then
  systemctl --user start t3code
  exit 1
fi
sudo nixos-rebuild switch --flake /etc/nixos#j2 --cores 4 --max-jobs 1
systemctl --user start t3code
```

Restarting interrupts agent turns, terminals and connected clients. A NixOS
rollback changes binaries/configuration, not databases; don't downgrade after
an application migration without checking compatibility or restoring the
pre-upgrade state backup.

## Move to nixpkgs

Set `services.t3code.package = pkgs.t3code` to override the flake's package
selection. Both packages expose `bin/t3`. Keep the service name, `--base-dir`,
working directory, provider PATH and Caddy routes unchanged.

For complete removal of the external input, replace its Home Manager module
with a local `systemd.user.services.t3code` definition using the same
`t3 serve --host 127.0.0.1 --port 3773 --base-dir /home/saleh/.t3 /home/saleh`
invocation. Install `pkgs.t3code` and retain the pairing wrapper. Check release
and state compatibility first, especially when nixpkgs packages an older version.
