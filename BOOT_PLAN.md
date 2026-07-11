# Guided NixOS Recovery ISO Plan

## Summary

Add a custom recovery/install ISO to this repo without changing `hosts/j2.nix`
unless explicitly approved later. The ISO will support two guided install modes:

- `multiboot`: preserve existing installed OSes, including Windows 11 or other
  Linux installs, and install NixOS only into user-approved free space.
- `single-boot-destructive`: wipe the selected disk and install only NixOS.

The plan supports multiboot preservation by design: the installer must not
delete, format, resize, or overwrite existing OS partitions unless the user
explicitly chooses the destructive single-boot mode.

For commands requiring `sudo`, the install docs and helper tooling should prompt
the user to run the privileged command externally, with context explaining why
the command is needed and what it will affect.

## Key Changes

- Add a reusable new-machine template, preferably `templates/new-computer.nix`,
  modeled after `hosts/j2.nix` but without j2-specific disk UUIDs, Pop!_OS
  entries, DisplayLink assumptions unless selected, or current-machine LUKS
  devices.
- Add a recovery ISO flake output, for example
  `packages.x86_64-linux.recoveryIso`, built from a dedicated ISO config.
- Add guided install tooling that:
  - Shows disks, partitions, filesystems, mountpoints, and likely installed OS
    partitions first.
  - Asks for install mode: `multiboot` or `single-boot-destructive`.
  - Asks for target Linux username.
  - Requires explicit target disk confirmation before partitioning.
  - Generates/imports new hardware config after the target filesystem is
    mounted.
- Keep current `j2` behavior intact. Any shared-module extraction from `j2`
  should be planned separately before touching daily-driver config.

## ISO Creation Workflow

Build the ISO from this repo:

```bash
nix build .#recoveryIso
```

Or, if exposed under packages:

```bash
nix build .#packages.x86_64-linux.recoveryIso
```

The built ISO appears under:

```bash
result/iso/*.iso
```

For a normal USB, ask the user to run the required `sudo dd` command externally.
Explain that it writes the ISO image directly to the selected USB device and can
overwrite the wrong disk if the device path is incorrect.

Example command to present to the user:

```bash
sudo dd if=result/iso/<iso-name>.iso of=/dev/<usb-device> bs=4M status=progress oflag=sync
```

For GLIM:

- Copy the ISO into GLIM's ISO directory.
- Reboot into the GLIM USB.
- Select the custom NixOS recovery ISO from the GLIM menu.

## Install Workflow

Boot the recovery ISO, connect to the network, clone or use the embedded repo
copy, then run the guided installer command. The installer asks for one mode.

### `multiboot`

This mode is intended for a machine that already has Windows 11, Linux, or other
OS partitions.

- Installer shows detected partitions and highlights likely EFI, Windows, Linux,
  swap, and unknown partitions.
- User confirms the target disk and the exact free space or new partitions to
  use for NixOS.
- Installer must not format existing EFI or OS partitions.
- Existing EFI partition may be mounted at `/mnt/boot/efi` only after
  confirmation.
- NixOS is installed into new Linux partitions only.
- GRUB is configured for NixOS plus detected existing OSes, with no hardcoded
  Pop!_OS entry.

### `single-boot-destructive`

This mode is intended for a NixOS-only machine.

- Installer shows the selected disk and requires a destructive typed
  confirmation.
- Installer wipes the selected disk.
- Creates EFI, `/boot`, encrypted NixOS root, btrfs subvolumes, and swap.
- Installs the generated new-computer host config.

After either mode:

- Set the user password.
- Restore secrets manually: SSH keys, `.bash_secrets`, rclone config, Tailscale
  login, browser/profile data.
- Reboot and select NixOS from firmware/GRUB.

Any `sudo` command in the install flow should be displayed for the user to run
manually with a short explanation of why the privilege is needed. The guided
installer may prepare commands and validate choices, but privileged disk writes
must be consent-forward and visible.

## Test Plan

- Verify existing host still evaluates:

  ```bash
  nix build .#nixosConfigurations.j2.config.system.build.toplevel
  ```

- Verify the ISO builds:

  ```bash
  nix build .#recoveryIso
  ```

- Boot ISO in a VM.
- Confirm installer refuses to partition unless a mode, username, target disk,
  and confirmation are supplied.
- Test `single-boot-destructive` in a disposable VM disk.
- Test `multiboot` against VM disks containing mock Windows EFI/NTFS and
  Linux/ext4/btrfs layouts.
- Smoke-test GLIM by copying the ISO to the GLIM USB and booting it.

## Assumptions

- Target machines are x86_64 UEFI systems.
- Default username can be suggested as `saleh`, but the installer asks every
  time.
- Current `hosts/j2.nix` should remain untouched unless later approved.
- Secrets and mutable app state stay outside Git and are restored separately.
- `single-boot-destructive` is the boot/menu-safe name for
  "single boot (destructive)".
