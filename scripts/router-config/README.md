# Router configuration and update recovery

This is an on-demand tool for two GL.iNet routers. It does not install timers,
perform firmware updates, back up automatically, or reconcile configuration in
the background. `check` and `plan` never create backups. `apply` defaults to a
preview. Even `backup` defaults to a preview, with no NAS connection.

Run backups on demand while SnapRAID is idle. The designated destination is
`u3:/mnt/pool/vault/backups/manual/routers/`.

Saleh authorized the first backup after confirming the sync had finished. That
attempt stopped at the empty SSH agent before contacting the NAS or routers;
no archive or baseline was created. Unlock the SSH key locally before retrying.

## Run it

From the editable checkout, without rebuilding NixOS:

```bash
nix run path:/etc/nixos#router-config -- --help
nix run path:/etc/nixos#router-config -- validate
nix run path:/etc/nixos#router-config -- check
nix run path:/etc/nixos#router-config -- plan main
nix run path:/etc/nixos#router-config -- plan office
nix run path:/etc/nixos#router-config -- backup
```

The default configuration is `~/.config/router-config/site.json`, outside Git.
A private site file has been prepared on j2 with the addresses confirmed during
the network repair. `site.example.json` is an anonymized template. The helper
uses the Nix-pinned Python, OpenSSH and age packages. The generated command is
also available through the local `~/.local/bin/router-config` launcher.

All SSH operations require an **already unlocked ordinary SSH agent** and known
host keys. No password login, automatic host-key acceptance, desktop keyring
fallback or browser prompt is performed. When needed, the owner can unlock the
key locally with `ssh-add ~/.ssh/id_ed25519`; its passphrase stays on the owner’s
terminal. The tool never obtains it. An empty agent fails before connecting.

The Beryl's site entry pins the known host key from its previously verified
address using `HostKeyAlias`; an address change cannot silently select a different
router. The NAS uses its Tailscale address and the existing `u3` host-key alias,
so the backup transport does not depend on a changing DHCP lease.

## First authorized backup and baseline

Only after SnapRAID is idle and Saleh requests the backup:

```bash
router-config backup --execute --accept-baseline
```

For a single router, put `main` or `office` after `backup`. The tool:

1. Checks the NAS hostname, mounted pool and running SnapRAID process. It does
   not stop SnapRAID, start services, change the NAS or fall back to its root disk.
2. Reads router identity, GL firmware version, runtime interfaces and UCI state.
   It rejects known subnet collisions, a disconnected WDS uplink, configuration
   drift and unexpected hardware before creating router archives.
3. Streams each router's native `sysupgrade -b -` configuration archive, together
   with its model, firmware, UCI inspection, backup file list, native archive checksum and installed
   package inventory. A native backup preserves files selected by the router's
   own backup rules; it is not a firmware image, package-binary backup or dump of
   the router's entire filesystem.
4. Encrypts the complete bundle to the configured SSH public key using age.
   No plaintext archive is written on j2 or u3. Router configuration is held in
   client memory during this command. OpenWrt may use its own temporary files.
5. Uploads a private temporary file in the requested NAS directory, verifies its
   SHA-256, publishes without overwriting existing archives, and writes a `.sha256`
   sidecar. SnapRAID and the pool mount are checked again before upload. This is
   a point-in-time guard: do not start another sync during the transfer.
6. With `--accept-baseline`, saves the selected core UCI settings privately on j2
   **after that router's upload succeeds**. These baseline files contain Wi-Fi
   passwords and other credentials: `~/.local/state/router-config/*.baseline.json`
   is mode 600 under a mode-700 directory. Keep them outside Git and the Nix store.

Each router is published independently. If the second router fails, the first
router's completed archive remains available and the command reports failure;
rerun after resolving the error. A completed upload is not a tested restore.
Preserve the matching SSH private key independently: the public key alone cannot
decrypt these archives. Updating to a different key does not re-encrypt old ones.

Until the first authorized baseline capture, checks and repairs cover the
explicit site file settings only: subnets, Beryl reservation and WDS settings.
After capture, they compare every saved option in `network`, `wireless`, `dhcp`,
`firewall`, `glconfig`, `repeater` and `system`. This includes Wi-Fi credentials,
reservations, DHCP/DNS options, firewall rules and GL settings in those packages.
Plugins, extra package configurations, scripts, keys and certificates are covered
only to the extent they appear in the router's native backup; inspect its backup
file list when live SSH access is available. Inventory alone does not reinstall
missing packages.

Explicit site-file policy overrides corresponding baseline options. For example,
changing an intended reservation does not leave contradictory old/new writes in
the repair plan. Other baseline options remain in effect.

## Updating and reapplying

1. Run `check`; fix failures before promoting a known-good baseline.
2. Explicitly request/run a backup while the NAS is idle.
3. Use the vendor's supported upgrade process and Keep Settings where supported.
   Keep the previous firmware image and its matching backup for recovery.
4. Run `check` and `plan main` / `plan office` after updating.
5. Review changed firmware and section layouts before permitting repair. The
   helper deliberately refuses `apply --execute` on a firmware version different
   from the reviewed site file or saved baseline. There is no force/ignore flag.
   Migrate a **copy** of the private baseline deliberately after reviewing the
   vendor's changes, keeping the old baseline for recovery. Do not solve a version
   mismatch by accepting the router's potentially reset settings as the baseline.
6. Apply an inspected plan when the firmware and model match:

```bash
router-config apply main --execute
router-config apply office --execute
```

A repair changes only saved option values and explicitly permitted reservation
creation. It preserves extra options introduced by firmware, and refuses missing
or differently typed sections, duplicate matches and uncommitted UCI edits.
Anonymous section selectors must be reviewed if ordering changes. Changing GL
network mode requires its own migration process and is never simulated by merely
setting `glconfig.general.mode`.

Before committing a repair, the tool retains touched configuration files in a
private router-local temporary directory and starts a finite 120-second rollback
timer. It reloads only related services. After a short delay, it reconnects and
checks all managed settings, runtime subnets and WDS status. It cancels rollback
only if those checks pass. A failed command or lost connection leaves rollback
armed: keep the router powered on for at least 120 seconds. This guard does not
survive a reboot or firmware flash. Concurrent repairs are refused while the
timer exists. Temporary rollback files are removed when the timer finishes.

Repair does not test every firewall policy or eliminate every possible service
regression. `check` separately probes admin HTTP, tests the NAS's gateway and
Ubuntu HTTPS access bound to Ethernet, and checks system DNS resolution. The DNS
check does not establish which interface carried DNS traffic. It reports j2's temporary Ethernet profile
if still active. It does not run apt, downloads, speed tests or backup operations.

## Native archive recovery

Whole native restores should use the matching router model and firmware. Do not
blindly import one router's archive onto the other or across firmware layouts.
The helper never flashes or reboots a router and does not automate a native
restore. A targeted repair is the supported automated recovery route.

To inspect/recover a saved bundle, first copy its `.age` file and `.sha256`
sidecar from u3 to a private local directory when authorized. Verify the sidecar
with `sha256sum -c`. Decrypt to a mode-600 local file in a mode-700 directory:

```bash
umask 077
age --decrypt --identity ~/.ssh/id_ed25519 --output bundle.tar.gz BACKUP.tar.gz.age
tar -tzf bundle.tar.gz
tar -xzf bundle.tar.gz metadata.json native-backup.tar.gz installed-packages.txt
```

Decryption may ask the owner for the private key's passphrase locally. This is an
explicit recovery action, never part of check, plan, backup or automated repair.
Read `metadata.json`, verify the native archive against `native_sha256`, and
follow the router's supported LuCI restore procedure for matching firmware.
Package inventory and native backup coverage require review before claiming that
every installed plugin or custom service has been recovered.

## Verification and remaining network checks

```bash
nix run path:/etc/nixos#router-config -- check --network-only
nix build path:/etc/nixos#checks.x86_64-linux.router-config-tests --no-link
```

The offline tests use synthetic configurations and mocked SSH. They exercise the
actual overlap regression, reservation identity, dry-run separation, firmware and
model guards, quoting, encryption bundle contents, atomic publication, private
baseline permissions and rollback confirmation. They do not contact u3 or routers.

Still verify through live SSH after key access is available:

- Main and IoT are separate `/24` networks with matching DHCP pools; inspect
  default gateway, DNS and reservations, especially the Beryl's DHCP MAC.
- Guest/IoT firewall isolation blocks router management and Main LAN access as
  intended; check the target subnet in rules added by the firmware update.
- Beryl is in WDS, has an active uplink and reconnects after an ordinary restart.
  Coordinate any deliberate disconnection/reboot test with the user.
- The switch uplink forwards traffic in both directions. Verify u3 reaches the
  gateway and Ubuntu HTTPS over Ethernet and resolves DNS, rather than relying on Tailscale
  presence or the router admin page alone.
- Remove j2's temporary `office-router-diagnostic` profile and reactivate its
  ordinary Ethernet profile only after that Ethernet path is verified working.
- Confirm native backup coverage includes any custom files/plugins. Do not
  promote a partially repaired network to a known-good baseline.

Vendor reference: GL.iNet's "How to export/import backup configuration files via
LuCI" and upgrade documentation; OpenWrt's UCI and sysupgrade documentation.
