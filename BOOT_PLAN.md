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
  entries, or current-machine LUKS devices. Include DisplayLink driver config
  and the related unfree package allowlist only as commented-out examples, so
  they are easy to enable later but disabled by default.
- Add a recovery ISO flake output, for example
  `packages.x86_64-linux.recoveryIso`, built from a dedicated ISO config.
- Add guided install tooling that:
  - Shows disks, partitions, filesystems, mountpoints, and likely installed OS
    partitions first.
  - Asks for install mode: `multiboot` or `single-boot-destructive`.
  - Asks for target Linux username.
  - Requires explicit target disk confirmation before dispatching to an install
    mode.
  - Generates/imports new hardware config after the target filesystem is
    mounted.
  - Provides separate mode commands:
    `nixos-recovery-multiboot` and
    `nixos-recovery-single-boot-destructive`.
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

If a custom output path is supplied with `-o`, use that path instead. For
example:

```bash
nice -n 10 ionice -c 3 nix build .#recoveryIso --max-jobs 1 --cores 4 -o result-recovery-iso
```

Then the ISO appears under:

```bash
result-recovery-iso/iso/*.iso
```

The `nice`/`ionice`/`--max-jobs`/`--cores` form is slower but safer on a
laptop because ISO compression can otherwise saturate CPU and make the machine
unresponsive.

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
copy, then run the guided installer command:

```bash
nixos-recovery-install
```

The installer shows detected storage, asks for one mode, asks for target
username and hostname, asks for a target disk path, and requires typing the
exact target disk path before mode-specific work is prepared.

### `multiboot`

This mode is intended for a machine that already has Windows 11, Linux, or other
OS partitions.

- Installer shows detected partitions and highlights likely EFI, Windows, Linux,
  swap, and unknown partitions.
- User confirms the target disk. The mode helper writes non-destructive mount
  guidance to `/tmp/nixos-recovery/actions/01-multiboot-mount-commands.txt`.
- User manually creates and mounts only the new NixOS partitions under `/mnt`.
- Installer must not format existing EFI or OS partitions.
- Existing EFI partition may be mounted at `/mnt/boot/efi` only after
  confirmation.
- NixOS is installed into new Linux partitions only.
- GRUB is configured for NixOS plus detected existing OSes, with no hardcoded
  Pop!_OS entry.
- After `/mnt` is mounted and `nixos-generate-config --root /mnt` has been run,
  finish with:

  ```bash
  nixos-recovery-install --finish --hostname <hostname> --username <username>
  ```

### `single-boot-destructive`

This mode is intended for a NixOS-only machine.

- Installer shows the selected disk and requires a destructive typed
  confirmation.
- The main installer prints an explicit privileged command for the user to run
  externally:

  ```bash
  sudo nixos-recovery-single-boot-destructive --disk /dev/<disk> --hostname <hostname> --username <username> --mapper <mapper>
  ```

- `nixos-recovery-single-boot-destructive` shows the selected disk again and
  requires typing `WIPE /dev/<disk>` before it wipes anything.
- The destructive mode command wipes the selected disk.
- Creates EFI, `/boot`, encrypted NixOS root, btrfs subvolumes, and swap.
- Runs `nixos-generate-config --root /mnt`.
- After disk setup completes, finish with:

  ```bash
  nixos-recovery-install --finish --hostname <hostname> --username <username>
  ```

The finish step copies the embedded repo to `/mnt/etc/nixos`, imports the
generated hardware config into a new host config based on
`templates/new-computer.nix`, updates the target flake, and writes a final
privileged install script to `/tmp/nixos-recovery/actions/02-finish-install.sh`.
Run that script externally with `sudo` because it calls `nixos-install` and
writes the target system and bootloader.

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
- Confirm `nixos-recovery-install --help`,
  `nixos-recovery-multiboot --help`, and
  `nixos-recovery-single-boot-destructive --help` work.
- Test `single-boot-destructive` in a disposable VM disk.
- Test `multiboot` against VM disks containing mock Windows EFI/NTFS and
  Linux/ext4/btrfs layouts.
- Confirm `multiboot` does not execute destructive partitioning or formatting
  commands automatically.
- Smoke-test GLIM by copying the ISO to the GLIM USB and booting it.

## Assumptions

- Target machines are x86_64 UEFI systems.
- Default username can be suggested as `saleh`, but the installer asks every
  time.
- Current `hosts/j2.nix` should remain untouched unless later approved.
- Secrets and mutable app state stay outside Git and are restored separately.
- `single-boot-destructive` is the boot/menu-safe name for
  "single boot (destructive)".
