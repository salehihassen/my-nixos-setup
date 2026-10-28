# T3 Code on J2

J2 runs the prebuilt server (`channel = "stable"`) from the independently pinned
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

Claude Pro subscription model IDs (`claude-pro/...`) are excluded from the
Codex and Pi source catalogs on j2. T3 also hides those entries for those
providers so an existing provider process cannot list stale cached models.
Keep subscription-backed Claude models available only through the Claude Code
provider below when updating these catalogs.

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

Select **Claude · CLIProxy + c3** (`claudeAgent`) and a `claude-pro/...`
model, such as `claude-pro/claude-opus-5-5`. The provider's Binary path is
`/etc/nixos/scripts/t3-claude-proxy`. Its custom models retain the exact Claude
IDs imported from the CLIProxy catalog; the bare built-in models are hidden.
Model options are retained where Claude's catalog supplies them. These settings
live in `~/.t3/userdata/settings.json`, independently of NixOS generations.

T3 bypasses the interactive `claude()` shell function and supplies an explicit
model ID. On October 27, 2026, the unwrapped launch reproduced
`400 unknown provider for model claude-opus-5-5`: the request reached CLIProxyAPI,
which needs the `claude-pro/` routing namespace. Supplying the qualified ID
resolved the error. The same unwrapped process also lacked OTel configuration.

The launcher reads only Claude's proxy variables from `~/.bash_secrets`, then
calls the existing `scripts/agent-otel-run claude` launcher. This loads the same
private telemetry credentials and `~/.config/agent-otel/claude-settings.json`
overlay as the working interactive CLI. Existing Claude settings and account
files stay in their normal locations. No telemetry environment is added to the
T3 service or login shell. Bare startup `--model` and `--fallback-model` values
are qualified using the existing Opus route; already qualified models and
aliases remain intact. Dated default models retain their configured IDs.
Use the qualified picker entries for subsequent model switches too.

Verified with T3's Agent SDK version 0.3.276, starting with proxy and telemetry
variables removed from the parent environment: Opus completed an inference and
Bash tool call through CLIProxyAPI. On c3, session
`be3654a3-a013-486a-a5f3-580526392b2d` produced 12 `claude-code` Loki events and
7 Langfuse observations (`AGENT`, `GENERATION`, `SPAN`, `TOOL`), with usage,
captured tool output, and zero errors. Claude metrics were also present in
Prometheus. Repeat a downstream check with the existing `verify-c3.py` helper
above, using the native Claude session ID. The SDK smoke test is distinct from
running a turn through T3's UI.

Run the isolated launcher regression check with:

```sh
python3 /etc/nixos/scripts/test_t3_claude_proxy.py
```

Provider settings reload live. The idle Claude process left by the failed run
was stopped so it cannot retain the previous launch environment. New Claude
processes use the launcher. No service restart or NixOS rebuild is needed.

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
service does not source shell startup files. The launcher above loads the
existing proxy setup for T3 explicitly. The service's
`T3CODE_DISABLE_AUTO_UPDATE=1` setting controls T3 itself, not Claude Code.

## Update or switch channel

Automatic application updates are disabled. The packaging flake tracks upstream
releases; updating its input leaves the system's nixpkgs pin unchanged.
For future updates, keep `packageVariant = "prebuilt"` and use this Nix workflow
instead of the update prompt's `npx t3@...` command. T3 can keep running during
the build.

```sh
cd /etc/nixos
nix flake update t3-code-nix
nixos-rebuild build --flake /etc/nixos#j2 --cores 4 --max-jobs 1
```

To switch channels or build variants, edit `channel`/`packageVariant` in
`home/t3code.nix` before building. J2 uses the stable prebuilt server to avoid
compiling T3 Code locally. Source builds also build a shared desktop bundle and
can take several minutes. Match remote client versions where required by T3
Code. The build command does not activate the new configuration; the switch
below does.

After a successful build, wait for active agent work to finish, then back up
state with the service stopped before switching. Run this from a terminal
outside T3, since stopping the service disconnects its sessions:

First, run this command by itself and complete any password prompt:

```sh
sudo -v
```

Then run the block below immediately in the same terminal. It uses `sudo -n`
to fail with an error instead of requesting a password inside the block. The
first check happens before T3 is stopped.

```sh
(
  set -e
  sudo -n true
  systemctl --user stop t3code
  trap 'systemctl --user start t3code' EXIT

  backup_dir="$HOME/.local/state/t3code-backups"
  install -d -m 700 "$backup_dir"
  (
    umask 077
    tar -C "$HOME" -czf "$backup_dir/$(date +%Y%m%dT%H%M%S).tar.gz" .t3
  )

  sudo -n nixos-rebuild switch --flake /etc/nixos#j2 --cores 4 --max-jobs 1
)
```

The exit trap starts T3 again even if the backup or switch fails. If `sudo -n`
reports that a password is required, run `sudo -v` separately again and rerun
the block. After the switch, verify the version and service status, then
reconnect your clients:

```sh
t3 --version
systemctl --user status t3code
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
