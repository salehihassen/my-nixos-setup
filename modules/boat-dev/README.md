# Boat.dev CLI

Opt in on a NixOS host by adding one entry to its `imports` list in
`hosts/<host>.nix`:

```nix
../modules/boat-dev
```

Remove that entry to exclude Boat on the next rebuild. The shared configuration
and other hosts do not install it. This package currently supports x86_64 Linux.

Apply the configuration using your usual rebuild command, for example:

```sh
sudo nixos-rebuild switch --flake /etc/nixos#j2
boat --version
boat onboard
```

`boat onboard` performs account setup; it can include plan checkout. Authentication
stays in your user configuration, outside Nix. Use explicit sandbox IDs: the
upstream installer's optional shell function for `current` is not installed.

## Updating

`package.nix` pins the official binary by release version and SHA-256. The
wrapper disables automatic updates with `BOAT_NO_UPDATE=1`; do not use
`boat self-update`. There is no dependency on a file in Downloads.

1. Select a production CLI release from
   <https://github.com/ariana-dot-dev/agent-server/releases>. Its tag must start
   with `boat-cli-v`; this repository also releases other products.
2. Prefetch its binary, replacing `VERSION` with the release number:

   ```sh
   nix store prefetch-file --json \
     'https://github.com/ariana-dot-dev/agent-server/releases/download/boat-cli-vVERSION/boat-linux-x64'
   ```

3. Update `version` and `src.hash` in `package.nix` with that version and the
   returned `hash`, then rebuild. The package checks `boat --version` during
   the build. Follow with `boat status` and your normal authenticated workflow.

The static binary needs no external shared libraries, but can invoke external
programs. Its wrapper supplies OpenSSH and xdg-utils for SSH/SCP and browser
opening. New releases may change runtime requirements; check real CLI behavior
after upgrades. Build checks do not contact Boat or create paid resources.

For any newly added files, run `git add` before evaluating this Git-backed flake.
