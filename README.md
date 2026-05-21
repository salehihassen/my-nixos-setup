## Overview

This repo represents my NixOS configs in `/etc/nixos` excluding privately managed files. I'm new to NixOS so beware what you copy from my setup.

configuration.nix
home.nix
flake.nix
flake.lock
home/
  noctalia.nix - Noctalia configs
assets/
  wallpaper/ - wallpaper images

## Setup you'll still need to perform manually

### General
- [ ] Download drivers for displaylink manager as prompted while building nixos
- [ ] Generate or copy ssh keys
- [ ] Modify username if not `saleh`
- [ ] Set password for user w/ `passwd`
### j2 specific

