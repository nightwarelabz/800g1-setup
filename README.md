# 800g1-setup

Post-install setup for **Ubuntu 26.04 LTS** on an **HP EliteDesk 800 G1**,
used as the primary house for development projects.

One script, safe to re-run. It sets up a build machine — it does not set
your git identity, generate SSH keys, or sign you in to anything.

## Run it

```sh
git clone https://github.com/nightwarelabz/800g1-setup.git
cd 800g1-setup
chmod +x setup.sh
./setup.sh
```

Options:

```sh
./setup.sh --dry-run          # print every action, change nothing
./setup.sh --with-tailscale   # also install Tailscale (sign-in is yours)
./setup.sh --help
```

Run it as your normal user, not root. It uses `sudo` where needed.
Log out and back in once afterwards, so the docker group and PATH
changes take effect.

## What it installs

- **Base:** git, GitHub CLI, build-essential, cmake, ninja, clang/LLVM,
  pkg-config, OpenSSH server, UFW (SSH allowed), jq, ripgrep, fd, bat,
  htop, tmux, vim, fwupd
- **Rust:** stable via rustup, plus rustfmt and clippy
- **Comigen / wgpu:** Vulkan loader + tools, Mesa Vulkan drivers,
  Wayland / X11 / xkbcommon development headers
- **Node:** LTS via nvm (set as default), corepack enabled
- **Python:** uv, plus pipx
- **Docker:** Docker Engine from Docker's official apt repo, with the
  buildx and compose plugins; your user is added to the `docker` group
- **Directories:** `~/projects`, `~/.local/bin`

Toolchains are deliberately installed via rustup / nvm / uv instead of
the distro packages, so the LTS base can stay stable while the
languages stay current.

## Hardware notes — HP EliteDesk 800 G1

- Haswell CPU (i5-4570 / i7-4790 class), Intel Q87 chipset,
  up to 32 GB DDR3 in the SFF / tower form factors.
- The integrated **Intel HD 4600** has only limited Vulkan support.
  This box is a build, storage and services house; it is not a modern
  GPU test machine. Judge wgpu/Comigen GPU performance on real
  GPU hardware.
- Best value upgrades before anything else: a SATA SSD if it still
  has a spinning disk, and at least 16 GB RAM.

## Why Ubuntu 26.04 LTS

Install once, supported for years, and it matches GitHub Actions and
most Docker/dev documentation — no twice-a-year distro upgrade
standing between you and the projects it houses.
