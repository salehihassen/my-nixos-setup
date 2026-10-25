# T3 Code on J2

J2 runs the alpha source server (`channel = "stable"`) from the independently pinned
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
state); the working directory is `/home/saleh`. The service uses npm-managed
Claude Code and Codex from `~/.npm-global/bin`, plus existing credentials in the
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

## Codex through CLIProxy with telemetry

Use the **Codex · CLIProxy + c3** provider (`codex-cliproxy`) for model
requests through CLIProxy and telemetry to the existing collector. It is the
environment default with `codex-plus/gpt-6.1-sol` and high reasoning. Existing
threads keep their own provider selection; select this provider in their model
picker to enable forwarding for subsequent turns.

Its Binary path is `/etc/nixos/scripts/t3-codex-proxy`. T3 starts `codex
app-server` directly and does not invoke the `co()` shell function. Codex
0.164.0 rejects `--profile` with `app-server`, so this executable reads
`~/.codex/cliproxy.config.toml` and supplies the equivalent configuration
overrides. It retains only the Codex proxy credential from the existing private
`~/.bash_secrets` loader, then invokes `scripts/agent-otel-run` to load scoped
telemetry credentials. It opts in to the app-server metrics pipeline. Secrets
stay out of T3's settings and process arguments.

The profile enables OTLP logs, traces and metrics. Do not source its telemetry
environment into the T3 systemd service or the login shell. The original Codex
provider remains available for direct authentication. Provider settings are
stored in `~/.t3/userdata/settings.json`, separately from NixOS generations.

To verify a thread, have its agent report `$CODEX_THREAD_ID` from a shell tool.
This is the Codex conversation ID; it differs from T3's thread ID. Select User
`j2` and that session in Langfuse, or query Loki in Grafana:

```logql
{host_name="j2", service_name="codex-app-server"} | conversation_id="<CODEX_THREAD_ID>"
```

Check app-server metrics with PromQL:

```promql
codex_api_request_total{host_name="j2", service_name="codex-app-server"}
```

The existing machine-local acceptance helper can query all three backends
without printing credentials:

```sh
session='<CODEX_THREAD_ID>'
ssh c3-relay "python3 - '$session'" \
  < "$HOME/.local/share/agent-otel-setup/verify-c3.py"
```

Verified after the generation switch on October 24, 2026: the active T3 thread
exported `codex-app-server` events, metrics, and Langfuse `GENERATION`, `SPAN`
and `TOOL` observations. Native Codex traces contain call structure and timing;
generation usage and tool input/output remain incomplete in Langfuse, as in
the existing CLI setup. Inspect Codex's Loki events for recorded content and
usage; an empty Langfuse usage field alone does not mean export failed.

## Claude Code provider

Claude Code is installed per user with npm, independently of the NixOS and
Home Manager generations. Run installation and updates as Saleh, without sudo:

```sh
npm install -g @anthropic-ai/claude-code@latest
command -v claude
claude --version
claude doctor
```

If npm blocks Claude's postinstall script, allow it for this installation only:

```sh
npm install -g @anthropic-ai/claude-code@latest --allow-scripts=@anthropic-ai/claude-code
```

Home Manager supplies Node.js and sets npm's prefix to `~/.npm-global`.
Both the interactive shell and T3's service search that prefix first. Nix
continues to provide `ripgrep`, `procps`, `bubblewrap`, `socat`, and the
`nix-ld` library environment, including ALSA for the native Claude binary.
Use Claude's `/sandbox` command to check its sandbox dependencies.

After updating, new Claude processes use the new executable. Restart T3 after
active agent work finishes if it retains an older provider process:

```sh
systemctl --user restart t3code
```

To downgrade, install a known-good npm version explicitly (replace `VERSION`):

```sh
npm install -g @anthropic-ai/claude-code@VERSION
```

Existing Claude updater settings still apply. If you need to stay on a specific
version, disable Claude's auto-updater with `DISABLE_AUTOUPDATER=1` in each
launch environment. NixOS rollbacks do not change this npm installation.

The npm installation supports the same proxy configuration as packaged Claude:
set `ANTHROPIC_BASE_URL` to an Anthropic Messages-compatible gateway, and use
`ANTHROPIC_AUTH_TOKEN` for bearer authentication or `ANTHROPIC_API_KEY` for
`x-api-key` authentication, according to the gateway. Keep credentials outside
this repository and the Nix store. Check the effective configuration with
Claude's `/status` command.

Shell exports affect Claude launched from that shell; the lingering T3 user
service does not source shell startup files. For T3, use Claude's private user
settings or supply the variables to the user service through a private systemd
`EnvironmentFile` outside this repository. Restart T3 after active work finishes
to apply changes to its environment. The service's
`T3CODE_DISABLE_AUTO_UPDATE=1` setting controls T3 itself, not Claude Code.

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
