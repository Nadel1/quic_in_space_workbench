# Quic in space workbench

## Installation and Setup

Nix has to be installed to execute this workbench. See [the official NixOS website](https://nixos.org/download/) for instructions.

> If the installation fails with ``~~> Setting up the build group nixbld groupadd: GID '30000' already exists``, first verify that this id is truly taken (`getent group 30000`). Look for a free range, for example by testing other group ids. Export the new id using ` export NIX_BUILD_GROUP_ID=<x>` and `export NIX_FIRST_BUILD_UID=<x>` and retry the installation. (see: [NixOS issue](https://github.com/NixOS/nix/issues/6224#issuecomment-1063294431))

We use experimental Nix features, namely `nix-command` and `flakes`  which need to be enabled first to work seamlessly. Modify your config file found under `~/.config/nix/nix.conf` with this line:

    experimental-features = nix-command flakes

Create the file and directory if they do not exist. 

To build all experiments execute

    nix build

    