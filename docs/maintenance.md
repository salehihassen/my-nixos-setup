# Routine NixOS maintenance

`scripts/nixos-maintain.sh check|build|test|switch|boot|update [HOST]` works
from any directory. It uses the checkout containing the script, defaults to
the current short hostname, and rejects hosts absent from that flake's
`nixosConfigurations`. Use the script's actual path when working in a worktree.
`b1` is an evaluation placeholder, not a ready-to-install server configuration.

| Operation | Effect | Sudo |
| --- | --- | --- |
| `check` | Evaluate flake outputs without building checks | No |
| `build` | Build the selected host; leave `result` in the checkout | No |
| `test` | Build and activate now without changing the boot default | Yes |
| `switch` | Build, activate now, and change the boot default | Yes |
| `boot` | Build and change the next boot default | Yes |
| `update` | Update `nixpkgs` and `home-manager`, show lock diff, check, build | No |

Builds use at most two jobs and four cores per job. Ordinary operations refuse
lock-file updates. `update` intentionally changes `flake.lock`; a failed
evaluation/build leaves the changed lock file for inspection and never activates
it. Review `git diff -- flake.lock`, then keep or revert those changes yourself.

```sh
/etc/nixos/scripts/nixos-maintain.sh check
/etc/nixos/scripts/nixos-maintain.sh build j2
/etc/nixos/scripts/nixos-maintain.sh update j2
# Review before explicitly activating:
/etc/nixos/scripts/nixos-maintain.sh switch j2
```

Add new files to Git before evaluating a Git-backed flake. A successful
`check` means evaluation passed; it does not build the checks or prove the host
will build. `build` does not activate or open desktop windows. `test` changes
the running system and can restart services. Do not run activation operations
on a different machine simply by selecting that machine's host name.

Other inputs are updated separately and deliberately:

```sh
nix flake update t3-code-nix --flake /etc/nixos
git -C /etc/nixos diff -- flake.lock
/etc/nixos/scripts/nixos-maintain.sh check j2
/etc/nixos/scripts/nixos-maintain.sh build j2
```

The existing `n-*` shell aliases remain independent of this command. In
particular, `n-update` can update all inputs and uses the current directory;
use the script for the bounded workflow above.

Recover the system with `sudo nixos-rebuild switch --rollback` or an older
boot-menu generation. This does not revert checkout files, editable dotfiles,
or application data. Keep Git and data recovery separate from system rollback.

The offline command tests stub Nix, rebuild, hostname, Git, and sudo. They verify
host rejection before updates/activation, explicit paths (including spaces),
working-directory independence, failure propagation, and no activation by
`update`. Run `python3 -B scripts/test_nixos_maintain.py` or build
`checks.x86_64-linux.maintenance-tests`. They do not exercise real activation.
