# NixOS configuration

This repository manages `j2`, my daily-driver NixOS laptop, and provides modules
to reuse on other machines. It uses flakes to pin dependencies, Home Manager to
manage the user environment, and GNU Stow to link editable dotfiles.

The current NixOS hosts and recovery ISO target `x86_64-linux` (Intel/AMD 64-bit
Linux). The standalone Home Manager helper accepts a `system` argument, but
other architectures have not been validated here. The desktop host template and
recovery installer assume UEFI; VPS boot requirements depend on the provider.

| Target | What to reuse | Current status |
| --- | --- | --- |
| J2 laptop | `hosts/j2.nix` and its Home Manager profiles | Daily-driver configuration |
| Another NixOS desktop | New host and hardware files, portable + desktop profiles | Template available; tailor it to the machine |
| NixOS VPS or headless VM | New host and hardware files, portable profile | No ready-to-deploy server template; `b1` is a placeholder |
| Other Linux distribution | Standalone Home Manager + Stow | Helper available; add your own `homeConfigurations` entry |

Installing Nix on another Linux distribution does not turn it into NixOS. On
those machines this repository can manage your user environment; the existing
distribution still manages system services, users, networking, and boot.

## What this repository builds

```text
flake.nix
├── nixosConfigurations.<host>
│   ├── configuration.nix          shared NixOS services and packages
│   ├── hosts/<host>.nix           machine-specific policy
│   ├── hosts/<host>-hardware.nix  generated disks and hardware
│   └── Home Manager modules
│       ├── home/portable.nix      shared CLI development environment
│       ├── home/desktop.nix       Niri, desktop applications, and user services
│       ├── home/snapshot-work.nix optional window/workspace/browser captures
│       ├── home/av-editor.nix     optional media applications
│       ├── home/hardware-design.nix  optional hardware design applications
│       └── home/<host>.nix        per-host user applications
├── homeModules.{portable,desktop,snapshot-work,av-editor,hardware-design}
├── lib.mkStandaloneHome           portable Home Manager on non-NixOS Linux
├── checks.x86_64-linux.*              standalone builds and snapshot checks
└── packages.x86_64-linux.recoveryIso
```

`mkHostFor` integrates Home Manager into every NixOS host. Its default profile
contains only `home/portable.nix`; desktop hosts must opt into the desktop module
explicitly. `j2` composes portable, desktop, snapshot-work, AV editor, hardware design, and
`home/j2.nix`, while `b1` currently receives only portable. Home Manager uses
the host's Nixpkgs package set, so host-level package policy such as `j2`'s
unfree allowlist also applies to
its Home Manager packages.

The ownership boundary is:

- **NixOS** owns system services, users, hardware, boot, and system packages.
- **Home Manager** owns user packages and generated integrations.
- **GNU Stow** links editable preferences from `dotfiles/` into `$HOME`.
- **Machine-local state** such as passwords, SSH keys, browser profiles,
  `.bash_secrets`, and rclone credentials stays outside Git.

For example, Stow owns the editable Ghostty and tmux configurations while Home
Manager installs Ghostty and generates `.config/tmux/nix-plugins.conf` with
pinned paths for Sensible, Resurrect, and Continuum.

## Editable checkout scripts and optional snapshots

Implemented and build-checked on NixOS (2026-10-04); the running generation has
not been switched. Ubuntu hardware/session validation remains outstanding.

A **checkout script** is executable source loaded from the writable Git checkout
at runtime, rather than a frozen copy in `/nix/store`. Home Manager installs small
`writeShellApplication` launchers with explicit interpreters and dependencies.
They use the absolute `dotfilesRoot`, so a checkout at `~/src/nixos-config` works
as well as `/etc/nixos`. Script edits apply on the next invocation; an already
running service needs a restart. Changing dependencies, the launcher, or checkout
location requires a switch. Deleting the checkout breaks these commands. Git
supplies their source history and rollback.

Stow continues to own editable application preferences. Home Manager must not
generate the same Niri KDL or other files that Stow links. Desktop-control uses
checkout scripts only, exposed as `desktop-control-stop`,
`desktop-control-service`, and `desktop-control-mcp`. Privileged host services
continue to run packaged executables.

Snapshot capture is a separate Home Manager module. `desktop.nix` does not import
it. A machine explicitly composes:

```nix
homeModules = [
  ./home/portable.nix
  ./home/desktop.nix
  ./home/snapshot-work.nix # omit on machines that do not want captures
];
```

Only snapshots support `programs.snapshot-work.sourceMode`: `"store"` (default)
packages the implementation; `"checkout"` executes editable source under
`dotfilesRoot/scripts/snapshot-work`. J2 selects checkout mode. Both expose
`capture-work`, share source and tests, and create private output under
`~/Pictures/snapshot-work/{UTC-start-timestamp}/`. Open `index.html` for the gallery;
`manifest.json` records coverage and errors. Chromium tabs get at least five
seconds each before capture. Niri traversal visits every window across monitors
and workspaces, bringing off-screen columns into view. This does not enumerate
hidden terminal panes or capture whole document scrollback. Browser session tab
counts remain best effort; an already enabled CDP endpoint gives exact target
enumeration. Screenshots cannot guarantee recovery of unsaved work.

```bash
capture-work                      # all windows, workspace views, Chromium tabs
capture-work --tab-delay 10000     # allow ten seconds per browser tab
capture-work --no-tabs             # omit tab switching
```

See [the capture documentation](scripts/snapshot-work/README.md) for recovery
limits, CDP, profile selection, and report formats. On the first activation,
the exact old `~/.local/bin/capture-work` launcher is backed up as
`capture-work.pre-home-manager`, then Home Manager owns that command path.
Unknown launchers are not overwritten. Old source under `~/.local/share/work-capture`
and all previous captures remain untouched; the active implementation comes
from this repository after switching.

The launcher supplies Node.js, Niri's CLI, grim, wl-clipboard, and ydotool. It does
not start a privileged daemon, restart browsers, reboot, or schedule captures.
Set `home.sessionVariables.YDOTOOL_SOCKET` for the host's daemon socket;
desktop-control and snapshots share it. A capture can override it in its caller
environment.

Standalone Linux gets Niri user units and portals from the desktop module;
NixOS retains system integration through its Niri module. Ubuntu still needs
graphics drivers, a login-session entry, authentication, and an appropriately
permitted ydotool daemon. Ubuntu 26/eGPU validation is deferred to the new
machine; a NixOS build does not validate those host integrations.

Validation covers the j2 system build, portable/desktop/desktop-plus-snapshot
standalone builds, 11 capture tests, wrapper execution in both source modes,
paths with spaces, argument forwarding, live script edits, and missing-checkout
errors. Temporary-home checks cover Stow package selection/removal and legacy
launcher migration. Niri's current KDL validates. No desktop capture, service
restart, system switch, or Ubuntu hardware test is performed by these checks.

## Where to make a change

| Change | Edit | Apply with |
| --- | --- | --- |
| Settings shared by all NixOS hosts | `configuration.nix` | `nixos-rebuild switch --flake /etc/nixos#<host>` |
| One machine's boot, hardware, or services | `hosts/<host>.nix` | The same NixOS rebuild command |
| User packages or Home Manager settings | `home/*.nix` and the host's module list in `flake.nix` | NixOS rebuild on these NixOS hosts; `home-manager switch` for standalone Linux |
| Editable application preferences | `dotfiles/<package>/...` | Usually reload the application; restow when adding or removing files |
| Package/input versions | `flake.lock`, via `nix flake update` | Rebuild or switch afterward |

On J2, Home Manager is integrated into NixOS: one `nixos-rebuild switch` applies
both. There is currently no standalone `homeConfigurations.j2` output, so do not
use a separate `home-manager switch --flake .#j2` command.

The Stow symlinks point to the **editable checkout**, not a frozen Nix store
copy. Edits to linked dotfiles take effect independently of a NixOS rebuild.
Keep that checkout at the configured `dotfilesRoot`; moving or deleting it
breaks the links.

## Make this configuration yours

Fork the repository or change its Git remote, then review these values before
activating it on another machine:

1. Choose a Linux `username` and set it in the host entry in `flake.nix`.
2. Set the machine hostname in `hosts/<host>.nix`.
3. Generate a new hardware file; never reuse another machine's hardware file.
4. Search for personal paths and replace the ones you want:

   ```bash
   rg --hidden -g '!.git/**' '/home/saleh|saleh|#j2' home hosts dotfiles flake.nix configuration.nix templates
   ```

   In particular, review Noctalia's wallpaper path, SSH configuration, aliases,
   and personal application commands. MPD already uses the configured user's
   home directory. The `n-*` rebuild aliases in `.bash_aliases` still target
   `.#j2` and assume you run them from this checkout.
5. Review the timezone, bootloader, graphics, power management, and desktop
   choices. The new-machine template enables a Niri desktop and GRUB by default.
6. Enable optional unfree packages only on the host that needs them. Claude Code
   and its unfree allowance are intentionally specific to `j2`; the template's
   commented allowance is only for optional DisplayLink support.
7. Set the target user's password with `passwd` and restore secrets separately.

`configuration.nix` sets `system.stateVersion`, and `home/portable.nix` sets
`home.stateVersion`, both to `25.11`. These select compatibility defaults; they
do not select package versions or mean the setup is outdated. Keep an existing
machine's values when adopting this repo. Currently they are shared assignments,
so supporting machines with different values requires moving them into per-host
and per-home configuration. See the
[NixOS stateVersion option](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/misc/version.nix).

## Common workflow

Run these commands from the checkout. New files must be added to Git before
normal flake evaluation will see them; edits to already tracked files do not
need a commit first:

```bash
git status
git add <new-files>
nix flake check --no-build
```

`nix flake check --no-build` checks evaluation. `nix flake check` additionally
builds portable, desktop, and desktop-plus-snapshot standalone activation
packages, snapshot parser/traversal tests, and store/checkout wrapper checks. Neither command builds every host or the recovery ISO, nor activates
Home Manager or tests Stow against your actual home directory. See the
[Nix command reference](https://nix.dev/manual/nix/2.34/command-ref/new-cli/nix3-flake-check.html).

For an existing host such as `j2`:

```bash
# Build without activating
sudo nixos-rebuild build --flake /etc/nixos#j2

# Activate without changing the boot default
sudo nixos-rebuild test --flake /etc/nixos#j2

# Activate now and make it the boot default
sudo nixos-rebuild switch --flake /etc/nixos#j2
```

One-time j2 migration note (2026-10-04): the read-only preflight found an existing
manually enabled T3Code symlink that Home Manager would refuse to replace. Before
this switch, move that link aside as your normal user (this does not stop the
running service), then switch as above:

```bash
mv -i ~/.config/systemd/user/default.target.wants/t3code.service \
  ~/Downloads/TODO/t3code.service.pre-home-manager
```

This is an existing local-state conflict, not a required step on fresh machines.
The repository does not automatically delete unrelated service links.

Use `sudo nixos-rebuild switch --rollback` or an older boot-menu generation to
roll back NixOS. This does not restore application data or Stow-managed dotfile
contents; those dotfiles follow Git. `test` changes the running system and may
restart services; it is not a simulation. See the
[NixOS configuration manual](https://nixos.org/manual/nixos/stable/#sec-changing-config).

Update pinned inputs deliberately, then rebuild:

```bash
nix flake update
git diff -- flake.lock
nix flake check --no-build
sudo nixos-rebuild build --flake /etc/nixos#j2
sudo nixos-rebuild switch --flake /etc/nixos#j2
```

J2's custom Caddy/Porkbun source has a fixed-output hash in
`hosts/j2-t3code.nix`. Recheck it after changing Nixpkgs, Go, or plugin versions.
A successful ordinary build can reuse previously cached source even when a
fresh CI build would produce a different hash. With the source already built,
force a fresh verification using:

```bash
nix build .#nixosConfigurations.j2.config.services.caddy.package.src \
  --rebuild --no-link -L
```

If this reports a hash mismatch, investigate the dependency changes, update the
source hash to the verified result, and rebuild j2. CI checks this source before
downloading/building the full desktop so failures surface earlier.

The repo follows `nixos-unstable` and Home Manager's default development branch,
with exact revisions in `flake.lock`. Updating the lock file does not activate
anything. Commit a working lock file along with the configuration changes.

J2 uses a pinned DisplayLink override with a manually supplied vendor ZIP. On a
fresh builder, use the exact `nix-prefetch-url --name displaylink-630.zip` command
and hash in `.github/workflows/ci.yml` before building J2. The unfree
allowlist alone does not supply that archive.

Stow runs automatically during Home Manager activation, after Home Manager links
its files. Back up existing dotfiles and preview conflicts before the first
switch (this needs `stow` installed):

```bash
bash /etc/nixos/scripts/stow-dotfiles.sh --dry-run
```

Differing existing files cause a conflict. The wrapper removes byte-for-byte
identical legacy files during a real restow so it can replace them with links;
the dry run does not perform that cleanup. Avoid having Home Manager and Stow
manage the same path. See [GNU Stow's conflict rules](https://www.gnu.org/software/stow/manual/html_node/Conflicts.html).
After activation, open a new login shell to load the session variables and Bash
helpers, then use:

```bash
dotfiles-stow-dry-run
dotfiles-stow
dotfiles-unstow
```

The portable module selects Bash, Git, Neovim, and tmux. The desktop
module adds Ghostty, Niri, Noctalia, wallpapers, and miscellaneous desktop
scripts. Modules compose the `dotfiles.stowPackages` list; activation and new
login shells receive its space-separated `DOTFILES_STOW_PACKAGES` value.
A direct script invocation with that variable unset retains the old all-packages
default. For a fresh portable-only dry run, specify it explicitly:

```bash
DOTFILES_STOW_PACKAGES='bash git neovim tmux' bash scripts/stow-dotfiles.sh --dry-run
```

Removing a module does not automatically unstow its existing editable files.
To remove only old desktop links, run the script with the desktop package list
and `--delete`; it removes Stow-owned links, not the source files. Personal Bash
aliases remain part of portable; review them before using it on a server or work machine.

`~/.ssh/config` and `~/.ssh/config.local` are local files, unmanaged by NixOS or
Stow. Put `Include ~/.ssh/config.local` at the top of `~/.ssh/config` to load
private settings; a missing include file is ignored. Home Manager enables the SSH agent.

## Add a NixOS machine

On a machine that already boots NixOS, preserve its stock configuration and
clone your fork. Run this from your home directory, using your intended normal
user account; `/etc/nixos.stock` must not already exist:

```bash
cd "$HOME"
sudo mv /etc/nixos /etc/nixos.stock
sudo install -d -m 0755 -o "$USER" -g users /etc/nixos
git clone <your-repository-url> /etc/nixos
cd /etc/nixos
```

Choose a hostname such as `laptop2`, then generate hardware configuration:

```bash
sudo nixos-generate-config --show-hardware-config \
  | tee hosts/laptop2-hardware.nix >/dev/null
cp templates/new-computer.nix hosts/laptop2.nix
```

Edit `hosts/laptop2.nix` so it imports `./laptop2-hardware.nix`, sets the
hostname, and matches the machine's boot, storage, graphics, and service needs.
Compare the bootloader settings with `/etc/nixos.stock/configuration.nix` and
the generated mount points. In particular, the template expects the EFI System
Partition at `/boot/efi`; a stock installation may mount it at `/boot`.
Then register it in `flake.nix`:

```nix
nixosConfigurations = {
  # Existing hosts...
  laptop2 = mkHostFor {
    hostModule = ./hosts/laptop2.nix;
    homeModules = [
      ./home/portable.nix
      ./home/desktop.nix
    ];
    username = "your-user";
  };
};
```

Omit `homeModules` for a portable user profile; that does not disable desktop
services or packages in the copied NixOS host module. For applications or
preferences unique to the new machine, create `home/laptop2.nix` and append it
to the list. The copied host module should retain hardware, services, desktop
session infrastructure, and administrative packages; place ordinary user
applications in the Home Manager modules. The current template still includes a
self-contained system-wide desktop package baseline, so remove entries that are
already supplied by `home/desktop.nix` while tailoring the copied host module.

If the editable checkout is not `/etc/nixos`, also set an absolute
`dotfilesRoot`. Track the new files, build safely, and only then switch:

```bash
git add flake.nix hosts/laptop2.nix hosts/laptop2-hardware.nix
nix flake check
sudo nixos-rebuild build --flake /etc/nixos#laptop2
sudo nixos-rebuild switch --flake /etc/nixos#laptop2
sudo passwd your-user
```

`hosts/b1.nix` is an evaluation placeholder, not a deployable host.

### NixOS VPS or headless VM

Start with the provider's working NixOS configuration and generated hardware
file. Create `hosts/vps1.nix` that imports `./vps1-hardware.nix`, sets the hostname,
and retains the provider's required bootloader and network settings. Register
it inside the existing `nixosConfigurations` block:

```nix
vps1 = mkHostFor {
  hostModule = ./hosts/vps1.nix;
  username = "your-user";
};
```

This selects portable Home Manager by default. Do not copy J2's disk UUIDs or
the desktop template's Niri, DisplayLink, UEFI, or Btrfs Docker assumptions.

Every host made with `mkHostFor` also imports `configuration.nix`, which
currently enables NetworkManager, systemd-resolved, OpenSSH with password and
keyboard-interactive authentication, and Docker. It puts the user in `wheel`
and `docker`. This is a shared development baseline, not a minimal server
profile; review it against the VPS provider's networking and your intended
services.

Add your public SSH key in the host module:

```nix
users.users.your-user.openssh.authorizedKeys.keys = [
  "ssh-ed25519 <your-public-key>"
];
```

Verify a separate key-based login before disabling password authentication.
Since the shared configuration sets those options directly, a host-specific
override needs `lib.mkForce` (and `{ lib, ... }:` in the host module arguments):

```nix
services.openssh.settings.PasswordAuthentication = lib.mkForce false;
services.openssh.settings.KbdInteractiveAuthentication = lib.mkForce false;
```

Build first, then apply from the VPS with the provider console available while
changing boot, networking, or SSH. Non-NixOS VPS machines use the standalone
Home Manager instructions below instead.

## Standalone Home Manager on Linux

For a non-NixOS x86_64 Linux machine, first
[install Nix](https://nix.dev/install-nix) and verify `nix --version` works.
Enable the command and flake features by adding this line to
`~/.config/nix/nix.conf` (create its parent directory if needed):

```ini
experimental-features = nix-command flakes
```

Clone the repository somewhere owned by the user, such as
`/home/your-user/src/nixos-config`. There are currently **no** exported
`homeConfigurations` entries. Add the following inside the `in { ... }` outputs
block in `flake.nix`, alongside `nixosConfigurations`, not inside it:

```nix
homeConfigurations."your-user@workstation" = mkStandaloneHome {
  username = "your-user";
  homeDirectory = "/home/your-user";
  dotfilesRoot = "/home/your-user/src/nixos-config";
  # portable.nix is always included by this helper. Optional additions:
  homeModules = [
    ./home/desktop.nix
    ./home/snapshot-work.nix
    {
      # Omit this to use the packaged snapshot source (the default).
      programs.snapshot-work.sourceMode = "checkout";
      home.sessionVariables.YDOTOOL_SOCKET = "/run/ydotoold/socket";
    }
  ];
};
```

Omit `homeModules` for CLI-only use. The modules are also exported as
`homeModules.desktop` and `homeModules.snapshot-work` for another flake to import;
pass `inputs` and `dotfilesRoot` along with the portable module when composing
the personal desktop outside this helper. Snapshot store mode can be used by
itself in an otherwise ordinary Home Manager configuration.

Before activating, back up conflicting dotfiles. Bootstrap using the Home
Manager version pinned by this repo (run as your normal user, without `sudo`):

```bash
cd /home/your-user/src/nixos-config
nix build '.#homeConfigurations.your-user@workstation.activationPackage'
nix shell --inputs-from . nixpkgs#stow --command bash scripts/stow-dotfiles.sh --dry-run
nix run --inputs-from . home-manager -- switch --flake '.#your-user@workstation'
```

`--inputs-from .` makes the first Home Manager command use this flake's pinned
input. After activation, start a new login shell. Home Manager installs its own
CLI, so later apply changes with:

```bash
home-manager switch \
  --flake /home/your-user/src/nixos-config#your-user@workstation
```

This installs the selected user environment. It does not configure the kernel,
bootloader, networking, Docker daemon, or a system login manager.
The current portable module also starts a user SSH agent and includes tools
such as Node.js, Neovim, ffmpeg, and X11 clipboard support; it is not a minimal
server package set. Desktop dotfiles are linked only when the desktop module is selected. Standalone
Home Manager expects a working Linux user environment, including systemd user
services for the SSH agent.

For a Niri desktop on Ubuntu, also complete host setup before logging into it:

- Install/configure the host's graphics driver. Follow Home Manager's
  [generic-Linux GPU guidance](https://nix-community.github.io/home-manager/usage/gpu-non-nixos.html),
  including its sudo setup helper when activation requests it. Proprietary
  NVIDIA userspace libraries must match the host driver version.
- Register a Wayland login-session entry that launches `niri-session` with the
  user's Nix profile environment loaded. The desktop module supplies Niri's
  user units, Xwayland satellite, and GNOME/GTK portals on generic Linux; the
  host provides login, device access, audio, and authentication. Avoid installing
  duplicate portal services from both package managers. Validate Noctalia's
  lock/unlock against host PAM instead of copying NixOS PAM files.
- Supply a ydotool daemon with `/dev/uinput` access and a restricted socket for
  the intended user/group. Match its client version and configure
  `home.sessionVariables.YDOTOOL_SOCKET`. This is needed for keyboard tab capture;
  importing a Home Manager module does not grant privileged device access.
- Review the editable output blocks in `dotfiles/niri/.config/niri/config.kdl`:
  they retain j2's monitor identities/modes. Adapt them in the new machine's
  checkout, along with wallpaper paths and other personal preferences. No new
  monitor-selection abstraction was added in this refactor.

Actual Ubuntu 26, eGPU, session login, and GPU validation remain future work on
the new machine. The inference stack is separate from the desktop modules.

See the [Home Manager standalone guide](https://nix-community.github.io/home-manager/nix-flakes/standalone.html)
for how flake-based user configurations work.

## Build and use the recovery ISO

The ISO contains a minimal NixOS installer, storage tools, the guided recovery
commands, and a tracked snapshot of this repository. Building it does not touch
any disks or partitions:

```bash
cd /etc/nixos
git status
nix flake check
nice -n 10 ionice -c 3 \
  nix build .#recoveryIso \
  --max-jobs 1 \
  --cores 4 \
  -o result-recovery-iso
ls result-recovery-iso/iso/
```

To make a USB installer, identify the whole USB device carefully with `lsblk`,
unmount its partitions, and write the exact ISO path:

```bash
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL
sudo dd \
  if=result-recovery-iso/iso/<exact-iso-name>.iso \
  of=/dev/<exact-usb-device> \
  bs=4M status=progress conv=fsync
```

`dd` destroys the contents of `of=`. A wrong device can erase an internal disk.
The ISO may instead be copied to a GLIM or Ventoy-style multiboot USB.

After booting the ISO and connecting to the network, run:

```bash
nixos-recovery-install
```

The installer displays the selected disk and requires exact confirmation before
showing either workflow:

- **`single-boot-destructive`** prints a separate `sudo` command that requires a
  second `WIPE /dev/...` confirmation. It creates EFI and `/boot` partitions, a
  LUKS-encrypted Btrfs root with subvolumes, and 16 GiB **unencrypted** swap.
  The EFI and `/boot` partitions are also unencrypted.
- **`multiboot`** never partitions, resizes, formats, or mounts existing OS
  partitions. It writes manual guidance to
  `/tmp/nixos-recovery/actions/01-multiboot-mount-commands.txt`; the operator must
  create NixOS partitions only in confirmed free space.

Once the intended filesystems are mounted under `/mnt` and
`nixos-generate-config --root /mnt` has completed, finish with the exact username
and hostname chosen earlier:

```bash
sudo nixos-recovery-install --finish \
  --hostname laptop2 \
  --username your-user
```

Before running the generated install script, review
`/mnt/etc/nixos/hosts/laptop2.nix` and its entry in `/mnt/etc/nixos/flake.nix`.
The finish helper copies the desktop template but registers only portable Home
Manager by default. For a full desktop, add `home/desktop.nix` alongside
`home/portable.nix` in that host's `homeModules` list as shown earlier. It does
not automatically copy J2's additional application profiles. Then install:

```bash
sudo bash /tmp/nixos-recovery/actions/02-finish-install.sh
```

The finish flow preserves the newly generated hardware configuration, adds the
new host to the target flake, runs `nixos-install`, makes `/etc/nixos` editable by
the target user and `nixcfg` group, and prompts for that user's password inside
the installed system.

The installed `/etc/nixos` is an editable snapshot, not a Git clone, because ISO
builds exclude `.git`. After the first boot, either initialize it as a new Git
repository or clone your fork and carry over the generated host module, hardware
file, and `flake.nix` host entry.

An ISO build confirms that the recovery environment composes successfully; it
does not prove destructive storage behavior. Test both workflows with disposable
VM disks before using the destructive mode on valuable hardware.

## Secrets and local state

Restore these manually after installation:

- User and root passwords.
- SSH keys, `~/.ssh/config`, and `~/.ssh/config.local`.
- `~/.bash_secrets` and API credentials.
- Rclone configuration and Tailscale login.
- Browser profiles and application data.

Never commit secrets, private keys, recovery keys, or generated credentials.
