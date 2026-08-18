# NixOS configuration

This flake builds complete NixOS hosts, a portable Home Manager CLI profile, and
a custom recovery ISO. It targets x86_64 Linux; the NixOS host template and
recovery installer assume a UEFI machine.

## What this repository builds

```text
flake.nix
├── nixosConfigurations.<host>
│   ├── configuration.nix          shared NixOS services and packages
│   ├── hosts/<host>.nix           machine-specific policy
│   ├── hosts/<host>-hardware.nix  generated disks and hardware
│   └── home.nix
│       ├── home/portable.nix      shared CLI development environment
│       └── desktop applications and services
├── lib.mkStandaloneHome           portable Home Manager on non-NixOS Linux
└── packages.x86_64-linux.recoveryIso
```

The ownership boundary is deliberate:

- **NixOS** owns system services, users, hardware, boot, and system packages.
- **Home Manager** owns user packages and generated integrations.
- **GNU Stow** links editable preferences from `dotfiles/` into `$HOME`.
- **Machine-local state** such as passwords, SSH keys, browser profiles,
  `.bash_secrets`, and rclone credentials stays outside Git.

For example, Stow owns the editable tmux configuration while Home Manager
generates `.config/tmux/nix-plugins.conf` with pinned paths for Sensible,
Resurrect, and Continuum.

## Make this configuration yours

Fork the repository or change its Git remote, then review these values before
activating it on another machine:

1. Choose a Linux `username` and set it in the host entry in `flake.nix`.
2. Set the machine hostname in `hosts/<host>.nix`.
3. Generate a new hardware file; never reuse another machine's hardware file.
4. Search for personal paths and replace the ones you want:

   ```bash
   rg '/home/saleh|username ? "saleh"' .
   ```

   In particular, review the MPD music directory in `home.nix`, Noctalia and
   wallpaper paths, aliases, and personal application commands.
5. Review the timezone, bootloader, graphics, power management, and desktop
   choices. The new-machine template enables a Niri desktop and GRUB by default.
6. Enable optional unfree packages only on the host that needs them. Claude Code
   and its unfree allowance are intentionally specific to `j2`; the template's
   commented allowance is only for optional DisplayLink support.
7. Set the target user's password with `passwd` and restore secrets separately.

## Common workflow

New files must be added to Git before normal flake evaluation will see them:

```bash
git status
git add <new-files>
nix flake check
```

For an existing host such as `j2`:

```bash
# Build without activating
sudo nixos-rebuild build --flake /etc/nixos#j2

# Activate until reboot
sudo nixos-rebuild test --flake /etc/nixos#j2

# Activate now and make it the boot default
sudo nixos-rebuild switch --flake /etc/nixos#j2
```

Use `sudo nixos-rebuild switch --rollback` or an older boot-menu generation to
roll back NixOS. Stow-managed files follow Git instead of NixOS generations.

Update pinned inputs deliberately, then rebuild:

```bash
nix flake update
```

Stow runs automatically after Home Manager activation. It refuses conflicting
files rather than overwriting them, so back up existing dotfiles before the first
switch. Later, use:

```bash
dotfiles-stow-dry-run
dotfiles-stow
dotfiles-unstow
```

## Add a NixOS machine

On a machine that already boots NixOS, preserve its stock configuration and
clone your fork:

```bash
sudo mv /etc/nixos /etc/nixos.stock
sudo install -d -o "$USER" -g users /etc/nixos
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
Then register it in `flake.nix`:

```nix
nixosConfigurations = {
  # Existing hosts...
  laptop2 = mkHostFor {
    hostModule = ./hosts/laptop2.nix;
    username = "your-user";
  };
};
```

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

## Standalone Home Manager on Linux

For a non-NixOS x86_64 Linux machine, install Nix and Home Manager, clone the
repository somewhere owned by the user, and add an output alongside the existing
flake outputs:

```nix
homeConfigurations."your-user@workstation" = mkStandaloneHome {
  username = "your-user";
  homeDirectory = "/home/your-user";
  dotfilesRoot = "/home/your-user/src/nixos-config";
};
```

Activate it with:

```bash
home-manager switch \
  --flake /home/your-user/src/nixos-config#your-user@workstation
```

This installs the portable CLI and dotfile environment. It does not configure
the kernel, bootloader, networking, Docker daemon, or NixOS desktop.

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
  LUKS-encrypted Btrfs root with subvolumes, and 16 GiB swap.
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
- SSH keys and `~/.ssh/config.local`.
- `~/.bash_secrets` and API credentials.
- Rclone configuration and Tailscale login.
- Browser profiles and application data.

Never commit secrets, private keys, recovery keys, or generated credentials.
