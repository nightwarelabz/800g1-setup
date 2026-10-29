#!/usr/bin/env bash
# setup.sh - Post-install setup for Ubuntu 26.04 LTS on an HP EliteDesk 800 G1
#            used as the primary house for development projects.
#
# What it installs:
#   - Base build tools: git, gh, build-essential, cmake, ninja, clang, pkg-config
#   - Rust (stable, via rustup) + Comigen/wgpu native build dependencies
#   - Node.js LTS (via nvm) and Python tooling (uv, pipx)
#   - Docker Engine (official Docker apt repo) + docker group for your user
#   - OpenSSH server, UFW firewall (SSH allowed), common CLI utilities
#
# Optional flags:
#   --with-tailscale   Also install Tailscale (you still sign in yourself)
#   --dry-run          Print every action without changing the system
#
# Properties:
#   - Idempotent: safe to re-run. Installed pieces are detected and skipped.
#   - No personal values are baked in: it does not set your git name/email,
#     add SSH keys, or sign you in to anything.
#   - Run it as your normal user (not root). It uses sudo where needed.
#
# Usage:
#   chmod +x setup.sh
#   ./setup.sh [--with-tailscale] [--dry-run]

set -euo pipefail

WITH_TAILSCALE=0
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --with-tailscale) WITH_TAILSCALE=1 ;;
    --dry-run)        DRY_RUN=1 ;;
    -h|--help)
      sed -n '2,28p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 [--with-tailscale] [--dry-run]" >&2
      exit 2
      ;;
  esac
done

log()  { printf '\n== %s ==\n' "$*"; }
info() { printf '   %s\n' "$*"; }
warn() { printf '!! %s\n' "$*" >&2; }

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

sudo_run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] sudo %s\n' "$*"
  else
    sudo "$@"
  fi
}

# ---------------------------------------------------------------- preflight

if [ "$(id -u)" -eq 0 ]; then
  warn "Run this as your normal user, not as root. It will use sudo itself."
  exit 1
fi

if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  if [ "${ID:-}" != "ubuntu" ]; then
    warn "This script targets Ubuntu. Detected ID='${ID:-unknown}'. Continuing anyway."
  fi
  if [ "${VERSION_ID:-}" != "26.04" ]; then
    warn "This script was written for Ubuntu 26.04 LTS. Detected '${VERSION_ID:-unknown}'."
    warn "Most steps still apply, but package names were only checked against 26.04."
  fi
else
  warn "Cannot read /etc/os-release. Continuing anyway."
fi

if [ "$DRY_RUN" -eq 0 ]; then
  log "Refreshing sudo credentials"
  sudo -v
fi

export DEBIAN_FRONTEND=noninteractive

# ------------------------------------------------------------- apt basics

log "Updating apt and installing base development tools"
sudo_run apt-get update
sudo_run apt-get install -y \
  git gh curl wget ca-certificates gnupg lsb-release software-properties-common \
  build-essential cmake ninja-build clang llvm pkg-config libssl-dev \
  python3 python3-venv python3-pip pipx \
  openssh-server ufw unzip zip jq ripgrep fd-find bat htop tmux vim \
  fwupd

# Ubuntu names these binaries fdfind/batcat; link the common names for scripts.
run mkdir -p "$HOME/.local/bin"
if [ -x /usr/bin/fdfind ]; then
  run ln -sf /usr/bin/fdfind "$HOME/.local/bin/fd"
fi
if [ -x /usr/bin/batcat ]; then
  run ln -sf /usr/bin/batcat "$HOME/.local/bin/bat"
fi

# ------------------------------------------------- Comigen / wgpu native deps
# Note: the 800 G1's Intel HD 4600 has only limited Vulkan support. These
# packages make native Rust/wgpu builds compile and run in software/CPU
# modes; they do not turn the iGPU into a modern Vulkan device.

log "Installing graphics / wgpu build dependencies"
sudo_run apt-get install -y \
  libvulkan-dev vulkan-tools mesa-vulkan-drivers \
  libwayland-dev libxkbcommon-dev libx11-dev libxrandr-dev libxi-dev \
  libgl1-mesa-dev

# ------------------------------------------------------------------- Rust

log "Installing Rust (stable) via rustup"
if [ -x "$HOME/.cargo/bin/rustc" ]; then
  info "Rust already installed: $("$HOME/.cargo/bin/rustc" --version)"
  run "$HOME/.cargo/bin/rustup" update stable
else
  if [ "$DRY_RUN" -eq 1 ]; then
    info "[dry-run] curl https://sh.rustup.rs | sh -s -- -y --default-toolchain stable"
  else
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --default-toolchain stable
  fi
fi
if [ -f "$HOME/.cargo/env" ]; then
  # shellcheck disable=SC1091
  . "$HOME/.cargo/env"
fi
if [ "$DRY_RUN" -eq 0 ] && command -v rustup >/dev/null 2>&1; then
  rustup component add rustfmt clippy || warn "Could not add rustfmt/clippy components."
fi

# ------------------------------------------------------------------ Node

log "Installing Node.js LTS via nvm"
NVM_VERSION="v0.40.3"
if [ -s "$HOME/.nvm/nvm.sh" ]; then
  info "nvm already installed."
else
  if [ "$DRY_RUN" -eq 1 ]; then
    info "[dry-run] install nvm $NVM_VERSION, then: nvm install --lts"
  else
    curl -sSf "https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh" | bash
  fi
fi
if [ "$DRY_RUN" -eq 0 ] && [ -s "$HOME/.nvm/nvm.sh" ]; then
  # shellcheck disable=SC1091
  . "$HOME/.nvm/nvm.sh"
  nvm install --lts
  nvm alias default 'lts/*'
  corepack enable || true
fi

# ----------------------------------------------------------------- Python

log "Installing Python tooling (uv)"
if [ -x "$HOME/.local/bin/uv" ] || command -v uv >/dev/null 2>&1; then
  info "uv already installed."
elif [ "$DRY_RUN" -eq 1 ]; then
  info "[dry-run] install uv from astral.sh"
else
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi
run pipx ensurepath

# ----------------------------------------------------------------- Docker

log "Installing Docker Engine (official Docker apt repo)"
if command -v docker >/dev/null 2>&1; then
  info "Docker already installed: $(docker --version)"
else
  if [ "$DRY_RUN" -eq 1 ]; then
    info "[dry-run] add Docker apt key + repo, install docker-ce and plugins"
  else
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME:-noble} stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y \
      docker-ce docker-ce-cli containerd.io \
      docker-buildx-plugin docker-compose-plugin
    sudo systemctl enable --now docker
  fi
fi
if [ "$DRY_RUN" -eq 0 ] && getent group docker >/dev/null 2>&1; then
  if ! id -nG "$USER" | grep -qw docker; then
    sudo usermod -aG docker "$USER"
    info "Added $USER to the docker group. Log out and back in for it to take effect."
  fi
fi

# ------------------------------------------------------------- SSH + firewall

log "Enabling OpenSSH server and UFW firewall"
sudo_run systemctl enable --now ssh
sudo_run ufw allow OpenSSH
if [ "$DRY_RUN" -eq 1 ]; then
  info "[dry-run] sudo ufw --force enable"
else
  sudo ufw --force enable
fi

# --------------------------------------------------------------- Tailscale

if [ "$WITH_TAILSCALE" -eq 1 ]; then
  log "Installing Tailscale"
  if command -v tailscale >/dev/null 2>&1; then
    info "Tailscale already installed."
  elif [ "$DRY_RUN" -eq 1 ]; then
    info "[dry-run] install Tailscale from pkgs.tailscale.com"
  else
    curl -fsSL https://tailscale.com/install.sh | sh
  fi
  info "Sign in yourself when ready:  tailscale up"
else
  info "Skipping Tailscale (pass --with-tailscale to include it)."
fi

# ------------------------------------------------------------------ dirs

log "Creating project directories"
run mkdir -p "$HOME/projects" "$HOME/.local/bin"

# ---------------------------------------------------------------- summary

log "Done"
cat <<'EOF'
Installed / checked:
  - git, gh, build tools, cmake/ninja/clang, OpenSSH, UFW (SSH allowed)
  - Rust stable (rustup) + rustfmt + clippy
  - Node.js LTS (nvm, default alias set) + corepack
  - Python: uv + pipx
  - Docker Engine + compose/buildx plugins
  - wgpu/Comigen native build dependencies

Not done on purpose (your call, your values):
  - No git name/email set. Run:
        git config --global user.name "Your Name"
        git config --global user.email "you@example.com"
  - No SSH keys generated or copied, no accounts signed in.
  - Tailscale only with --with-tailscale, and it never signs in for you.

Remember:
  - Log out and back in once, so the docker group and PATH changes apply.
  - On this machine the Intel HD 4600 is a build/CPU graphics path,
    not a modern Vulkan GPU. Judge Comigen GPU performance elsewhere.
EOF
