#!/usr/bin/env bash
# =============================================================================
#  setup.sh — Restore your HyDE + Arch setup on a fresh machine
#
#  Prerequisites:
#    • Arch Linux base install complete (pacstrap, genfstab, chroot done)
#    • Booted into the new system as a normal user with sudo access
#    • Internet connection active
#    • This repo cloned: git clone <your-repo-url> ~/dotfiles
#
#  Usage:
#    ./setup.sh                 # full setup (recommended for a fresh machine)
#    ./setup.sh --skip-hyde     # skip HyDE installer (if already installed)
#    ./setup.sh --skip-packages # skip all package installation
#    ./setup.sh --configs-only  # only restore dotfiles/configs, nothing else
#
#  Everything is logged to setup.log in the repo directory.
#  If something fails, check that file first.
# =============================================================================

# Exit on error, treat unset vars as errors, fail on pipe errors.
# 'set -e' means if any command fails, the script stops immediately.
# This prevents cascading failures where one broken step corrupts the next.
set -euo pipefail

# Resolve paths relative to the script, not the caller's working directory.
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="$DOTFILES_DIR/setup.log"

# ── Flags ─────────────────────────────────────────────────────────────────────
SKIP_HYDE=false
SKIP_PACKAGES=false
CONFIGS_ONLY=false

for arg in "$@"; do
  case $arg in
  --skip-hyde) SKIP_HYDE=true ;;
  --skip-packages) SKIP_PACKAGES=true ;;
  # --configs-only implies both skips — useful for re-applying dotfiles
  # on an already-set-up machine without reinstalling anything
  --configs-only)
    SKIP_HYDE=true
    SKIP_PACKAGES=true
    CONFIGS_ONLY=true
    ;;
  esac
done

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# 'tee -a' writes to stdout AND appends to the log file simultaneously,
# so you can watch progress and review the full log later.
log() { echo -e "${GREEN}  ✔${NC}  $1" | tee -a "$LOGFILE"; }
section() { echo -e "\n${CYAN}${BOLD}▶ $1${NC}" | tee -a "$LOGFILE"; }
warn() { echo -e "${YELLOW}  ⚠${NC}  $1" | tee -a "$LOGFILE"; }
error() {
  echo -e "${RED}  ✖${NC}  $1" | tee -a "$LOGFILE"
  exit 1
}
skip() { echo -e "     ${YELLOW}skip${NC}  $1" | tee -a "$LOGFILE"; }

# ── Preflight checks ──────────────────────────────────────────────────────────
echo -e "\n${BOLD}╔══════════════════════════════════════════╗"
echo -e "║       HyDE Dotfiles — Fresh Setup        ║"
echo -e "╚══════════════════════════════════════════╝${NC}"
echo "(logging to $LOGFILE)"
echo "" | tee "$LOGFILE"

# Running as root breaks home directory detection and package builds (makepkg
# refuses to run as root). Always run as a normal user with sudo access.
[[ $EUID -eq 0 ]] && error "Do NOT run as root. Run as your normal user with sudo access."
command -v pacman &>/dev/null || error "pacman not found — this script is Arch Linux only."

echo -e "  User         : ${CYAN}$USER${NC}"
echo -e "  Home         : ${CYAN}$HOME${NC}"
echo -e "  Dotfiles dir : ${CYAN}$DOTFILES_DIR${NC}"
echo -e "  Skip HyDE    : $SKIP_HYDE"
echo -e "  Skip packages: $SKIP_PACKAGES"
echo ""
read -rp "  Looks good? Press Enter to continue (Ctrl+C to abort)... "

# =============================================================================
# STEP 1 — SYSTEM UPDATE & BASE DEPENDENCIES
#
# Always update before installing anything. Partial upgrades (installing new
# packages without updating the system first) can break things on Arch.
# The base-devel group is required by makepkg to build AUR packages.
# =============================================================================
section "System update & base deps"

sudo pacman -Syu --noconfirm 2>&1 | tee -a "$LOGFILE"
log "System updated"

sudo pacman -S --needed --noconfirm \
  git base-devel curl wget rsync \
  networkmanager pipewire wireplumber \
  xdg-user-dirs xdg-utils \
  2>&1 | tee -a "$LOGFILE"
log "Base dependencies installed"

# Enable NetworkManager so internet works after reboot.
# '|| true' prevents the script from stopping if the service is already running.
sudo systemctl enable --now NetworkManager 2>&1 | tee -a "$LOGFILE" || true
xdg-user-dirs-update # Creates ~/Downloads, ~/Pictures etc. if they don't exist
log "XDG user dirs set up"

# =============================================================================
# STEP 2 — RESTORE pacman.conf
#
# Must happen BEFORE any package installation. Our pacman.conf enables:
#   • multilib          — 32-bit libraries (Steam, Wine, etc.)
#   • chaotic-aur       — pre-built AUR packages (faster than building)
#   • Custom options    — ILoveCandy, ParallelDownloads=5, Color, etc.
#
# Without this step, pacman wouldn't know about chaotic-aur and would fail
# to install packages that come from it.
# =============================================================================
section "pacman.conf"

if [ -f "$DOTFILES_DIR/system/pacman.conf" ]; then
  sudo cp "$DOTFILES_DIR/system/pacman.conf" /etc/pacman.conf
  log "pacman.conf restored (chaotic-aur, multilib, ILoveCandy, ParallelDownloads)"
else
  warn "system/pacman.conf not found — using Arch default config"
fi

# =============================================================================
# STEP 3 — CHAOTIC-AUR
#
# chaotic-aur provides pre-compiled AUR packages, which means no waiting for
# local compilation. It needs its own GPG key trust chain before pacman will
# accept packages from it.
#
# Order matters:
#   1. Import + locally sign the chaotic-aur key
#   2. Install the keyring package (which adds more trusted keys)
#   3. Install the mirrorlist package (provides /etc/pacman.d/chaotic-mirrorlist)
#   4. Overwrite with our saved mirrorlist for consistent mirror selection
# =============================================================================
section "chaotic-aur repository"

if pacman-conf --repo-list 2>/dev/null | grep -q "chaotic-aur"; then
  log "chaotic-aur already configured"
else
  log "Setting up chaotic-aur..."

  if [ -f "$DOTFILES_DIR/system/pacman.d/chaotic-mirrorlist" ]; then
    # We have a saved mirrorlist — set up keyring first, then use our mirrors
    sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com 2>&1 | tee -a "$LOGFILE"
    sudo pacman-key --lsign-key 3056513887B78AEB 2>&1 | tee -a "$LOGFILE"
    sudo pacman -U --noconfirm \
      'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
      'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' \
      2>&1 | tee -a "$LOGFILE"
    sudo cp "$DOTFILES_DIR/system/pacman.d/chaotic-mirrorlist" /etc/pacman.d/chaotic-mirrorlist
    log "chaotic-aur configured with saved mirrorlist"
  else
    # No saved mirrorlist — use whatever chaotic-aur defaults to
    sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com 2>&1 | tee -a "$LOGFILE"
    sudo pacman-key --lsign-key 3056513887B78AEB 2>&1 | tee -a "$LOGFILE"
    sudo pacman -U --noconfirm \
      'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
      'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' \
      2>&1 | tee -a "$LOGFILE"
    log "chaotic-aur configured (default mirrorlist)"
    warn "Add [chaotic-aur] section to /etc/pacman.conf if not already there"
  fi
fi

# Sync package databases to include the new repos we just added
sudo pacman -Sy 2>&1 | tee -a "$LOGFILE"
log "Package database synced"

# =============================================================================
# STEP 4 — YAY (AUR HELPER)
#
# yay is built from the AUR using makepkg. We use a temp directory so the
# build files don't clutter the home directory. After install, yay handles
# all future AUR package installation.
# =============================================================================
section "yay (AUR helper)"

if command -v yay &>/dev/null; then
  log "yay already installed — skipping"
else
  log "Building yay from AUR..."
  BUILD_DIR=$(mktemp -d) # Temporary dir, auto-cleaned by OS on reboot
  git clone https://aur.archlinux.org/yay.git "$BUILD_DIR/yay" 2>&1 | tee -a "$LOGFILE"
  (cd "$BUILD_DIR/yay" && makepkg -si --noconfirm) 2>&1 | tee -a "$LOGFILE"
  rm -rf "$BUILD_DIR"
  log "yay installed"
fi

# =============================================================================
# STEP 5 — HyDE INSTALL
#
# HyDE's official installer handles:
#   • Installing Hyprland and all its dependencies
#   • Setting up waybar, rofi, dunst, sddm and their default configs
#   • Installing HyDE scripts and the Hyde CLI
#
# We install HyDE BEFORE restoring our dotfiles so that HyDE's defaults are
# laid down first — then our configs overwrite them in the steps that follow.
# This is the correct order to avoid HyDE overwriting our restored configs.
#
# If ~/HyDE already exists (e.g. re-running the script), we git pull + reinstall
# rather than cloning fresh, to avoid the "directory already exists" error.
# =============================================================================
section "HyDE (HyDE-Project/HyDE)"

if $SKIP_HYDE; then
  warn "HyDE install skipped (--skip-hyde)"
else
  if [ -d "$HOME/HyDE" ]; then
    warn "~/HyDE already exists — pulling latest and re-running installer"
    (cd "$HOME/HyDE" && git pull && bash install.sh) 2>&1 | tee -a "$LOGFILE"
  else
    log "Cloning HyDE..."
    git clone --depth 1 https://github.com/HyDE-Project/HyDE "$HOME/HyDE" 2>&1 | tee -a "$LOGFILE"
    log "Running HyDE installer (go make a coffee — this takes a while)..."
    (cd "$HOME/HyDE" && bash install.sh) 2>&1 | tee -a "$LOGFILE"
  fi
  log "HyDE installed"
fi

# =============================================================================
# STEP 6 — PACMAN PACKAGES
#
# We only install packages that aren't already present. This makes the step
# idempotent — safe to run multiple times without reinstalling everything.
#
# Packages are checked one-by-one with 'pacman -Qi' (query installed) and
# only unrecognised ones go into the MISSING array. A single bulk install
# call is then made for efficiency.
# =============================================================================
section "pacman packages"

if $SKIP_PACKAGES; then
  warn "Package install skipped (--skip-packages)"
elif [ ! -f "$DOTFILES_DIR/packages/pacman.txt" ]; then
  warn "packages/pacman.txt not found — skipping"
else
  MISSING=()
  while IFS= read -r pkg; do
    # Skip blank lines and comments (lines starting with #)
    [[ -z "$pkg" || "$pkg" == \#* ]] && continue
    pacman -Qi "$pkg" &>/dev/null || MISSING+=("$pkg")
  done <"$DOTFILES_DIR/packages/pacman.txt"

  if [ ${#MISSING[@]} -gt 0 ]; then
    sudo pacman -S --needed --noconfirm "${MISSING[@]}" 2>&1 | tee -a "$LOGFILE" ||
      warn "Some packages failed — check $LOGFILE"
    log "${#MISSING[@]} pacman packages installed"
  else
    log "All pacman packages already present"
  fi
fi

# =============================================================================
# STEP 7 — AUR PACKAGES
#
# Same approach as step 6 but using yay instead of pacman.
# AUR packages include anything from chaotic-aur too — 'pacman -Qqem' captures
# all foreign packages regardless of which AUR helper installed them.
# =============================================================================
section "AUR packages"

if $SKIP_PACKAGES; then
  warn "AUR install skipped"
elif [ ! -f "$DOTFILES_DIR/packages/aur.txt" ]; then
  warn "packages/aur.txt not found — skipping"
else
  AUR_MISSING=()
  while IFS= read -r pkg; do
    [[ -z "$pkg" || "$pkg" == \#* ]] && continue
    pacman -Qi "$pkg" &>/dev/null || AUR_MISSING+=("$pkg")
  done <"$DOTFILES_DIR/packages/aur.txt"

  if [ ${#AUR_MISSING[@]} -gt 0 ]; then
    yay -S --needed --noconfirm "${AUR_MISSING[@]}" 2>&1 | tee -a "$LOGFILE" ||
      warn "Some AUR packages failed — check $LOGFILE"
    log "${#AUR_MISSING[@]} AUR packages installed"
  else
    log "All AUR packages already present"
  fi
fi

# =============================================================================
# STEP 8 — VSCodium EXTENSIONS
#
# Extensions are stored as a list of extension IDs in packages/codium-extensions.txt
# (generated by 'codium --list-extensions' in backup.sh). We reinstall them
# one by one since there's no bulk install command.
# '--force' skips the "already installed" confirmation prompt.
# =============================================================================
section "VSCodium / Code-OSS extensions"

if $SKIP_PACKAGES; then
  warn "Skipped (--skip-packages)"
elif [ -f "$DOTFILES_DIR/packages/codium-extensions.txt" ]; then
  if command -v codium &>/dev/null || command -v code-oss &>/dev/null; then
    CMD=$(command -v codium 2>/dev/null || command -v code-oss)
    while IFS= read -r ext; do
      [[ -z "$ext" ]] && continue
      "$CMD" --install-extension "$ext" --force 2>&1 | tee -a "$LOGFILE" || true
    done <"$DOTFILES_DIR/packages/codium-extensions.txt"
    log "VSCodium extensions installed"
  else
    warn "codium/code-oss not found — install it first, then run:"
    warn "  xargs -a packages/codium-extensions.txt -I{} codium --install-extension {}"
  fi
else
  skip "packages/codium-extensions.txt (not found)"
fi

# =============================================================================
# STEP 9 — pipx TOOLS
#
# pipx installs Python CLI tools into isolated virtualenvs under ~/.local/share/pipx.
# They appear in PATH via ~/.local/bin but aren't managed by pacman or yay.
# =============================================================================
section "pipx global tools"

if $SKIP_PACKAGES; then
  warn "Skipped (--skip-packages)"
elif [ -f "$DOTFILES_DIR/packages/pipx.txt" ] && [ -s "$DOTFILES_DIR/packages/pipx.txt" ]; then
  if ! command -v pipx &>/dev/null; then
    sudo pacman -S --needed --noconfirm python-pipx 2>&1 | tee -a "$LOGFILE"
  fi
  while IFS= read -r tool; do
    [[ -z "$tool" ]] && continue
    pipx install "$tool" 2>&1 | tee -a "$LOGFILE" || warn "pipx: $tool failed"
  done <"$DOTFILES_DIR/packages/pipx.txt"
  log "pipx tools installed"
else
  skip "packages/pipx.txt (not found or empty)"
fi

# =============================================================================
# STEP 10 — RESTORE ~/.config
#
# All directories from configs/ are restored first.
# configs/_files/ contains the standalone files (mimeapps.list, kdeglobals etc.)
# that live directly in ~/.config rather than in a subdirectory.
#
# Note: HyDE was installed first (step 5) so its default configs already exist.
# This rsync overwrites them with YOUR configs, which is exactly what we want.
# =============================================================================
section "Restoring ~/.config"
mkdir -p "$HOME/.config"

if [ -d "$DOTFILES_DIR/configs" ]; then
  for src in "$DOTFILES_DIR/configs"/*/; do
    name=$(basename "$src")
    [[ "$name" == "_files" ]] && continue # handle _files separately below
    dest="$HOME/.config/$name"
    mkdir -p "$dest"
    rsync -a "$src" "$dest/" 2>&1 | tee -a "$LOGFILE"
    log "~/.config/$name"
  done

  # Restore standalone config files (mimeapps.list, kdeglobals, etc.)
  if [ -d "$DOTFILES_DIR/configs/_files" ]; then
    for src in "$DOTFILES_DIR/configs/_files"/*; do
      [ -f "$src" ] || continue
      cp "$src" "$HOME/.config/$(basename "$src")"
      log "~/.config/$(basename "$src") (file)"
    done
  fi
else
  warn "configs/ not found — skipping"
fi

# =============================================================================
# STEP 11 — RESTORE HOME DOTFILES
#
# Shell configs, .gitconfig, and .ssh/config are restored from shell/.
# Existing files are backed up with a .bak extension before overwriting,
# so nothing is lost if you need to roll back.
#
# .ssh/config is handled separately because it needs 600 permissions
# (SSH refuses to use config files that are world-readable).
# =============================================================================
section "Restoring home dotfiles"

if [ -d "$DOTFILES_DIR/shell" ]; then
  for f in "$DOTFILES_DIR/shell"/.*; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    [[ "$name" == "." || "$name" == ".." ]] && continue
    [[ "$name" == "ssh" ]] && continue # handled separately below
    # Back up any existing file so nothing is silently overwritten
    [ -f "$HOME/$name" ] && cp "$HOME/$name" "$HOME/${name}.bak"
    cp "$f" "$HOME/$name"
    log "$name → ~/$name"
  done

  # .ssh/config must be 600 — SSH ignores it (or refuses) if it's more permissive
  if [ -f "$DOTFILES_DIR/shell/ssh/config" ]; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    cp "$DOTFILES_DIR/shell/ssh/config" "$HOME/.ssh/config"
    chmod 600 "$HOME/.ssh/config"
    log ".ssh/config restored (permissions: 600)"
  fi
else
  warn "shell/ not found — skipping"
fi

# =============================================================================
# STEP 12 — OH-MY-ZSH
#
# oh-my-zsh is a zsh framework that manages themes and plugins.
# We detect whether it's needed by checking if .zshrc references it.
# RUNZSH=no and CHSH=no prevent the installer from immediately switching
# shells and launching zsh before the rest of our setup is done.
# =============================================================================
section "oh-my-zsh"

if grep -q "oh-my-zsh" "$HOME/.zshrc" 2>/dev/null; then
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    log "Installing oh-my-zsh..."
    RUNZSH=no CHSH=no \
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
      2>&1 | tee -a "$LOGFILE"
    log "oh-my-zsh installed"
  else
    log "oh-my-zsh already present"
  fi
else
  skip "oh-my-zsh (not referenced in .zshrc)"
fi

# =============================================================================
# STEP 13 — RESTORE ~/.local/bin
#
# Custom scripts (hydectl, hyde-shell, vault_toggle.sh, env, env.fish) are
# restored and made executable. Large binaries (copilot, claude, uv, uvx)
# were excluded from backup and are reinstalled separately here.
#
# 'chmod +x' on everything is safe — these are all scripts we wrote or
# knowingly included, not random files from the internet.
# =============================================================================
section "~/.local/bin"

if [ -d "$DOTFILES_DIR/local_bin" ] && [ "$(ls -A "$DOTFILES_DIR/local_bin" 2>/dev/null)" ]; then
  mkdir -p "$HOME/.local/bin"
  rsync -a "$DOTFILES_DIR/local_bin/" "$HOME/.local/bin/"
  find "$HOME/.local/bin" -type f -exec chmod +x {} \;
  log "~/.local/bin restored + chmod +x ($(ls "$DOTFILES_DIR/local_bin" | wc -l) scripts)"
else
  skip "local_bin/ (empty or not found)"
fi

# uv/uvx: Python package manager — excluded from git because it's a compiled
# binary. Installed fresh via the official one-liner.
if [ ! -f "$HOME/.local/bin/uv" ]; then
  if command -v uv &>/dev/null; then
    skip "uv (already in PATH)"
  else
    log "Installing uv (Python package manager)..."
    curl -LsSf https://astral.sh/uv/install.sh | sh 2>&1 | tee -a "$LOGFILE" || warn "uv install failed"
  fi
fi

# =============================================================================
# STEP 14 — RESTORE ~/.local/share
#
# HyDE data, wallbash colour templates, custom .desktop files, and other
# app share data. This is what makes the desktop look and behave exactly
# as it did on the original machine beyond just config files.
# =============================================================================
section "~/.local/share"

if [ -d "$DOTFILES_DIR/local_share" ]; then
  for src in "$DOTFILES_DIR/local_share"/*/; do
    name=$(basename "$src")
    dest="$HOME/.local/share/$name"
    mkdir -p "$dest"
    rsync -a "$src" "$dest/" 2>&1 | tee -a "$LOGFILE"
    log "~/.local/share/$name"
  done
else
  skip "local_share/ not found"
fi

# =============================================================================
# STEP 15 — RESTORE GTK THEMES, ICON THEMES, FONTS
#
# Themes and icons go to ~/.local/share/themes and ~/.local/share/icons.
# Fonts need fc-cache to be rebuilt after copying so apps can find them.
# =============================================================================
section "Themes & icons"
mkdir -p "$HOME/.local/share"

if [ -d "$DOTFILES_DIR/themes" ] && [ "$(ls -A "$DOTFILES_DIR/themes" 2>/dev/null)" ]; then
  mkdir -p "$HOME/.local/share/themes"
  rsync -a "$DOTFILES_DIR/themes/" "$HOME/.local/share/themes/"
  log "GTK themes restored"
else
  skip "themes/ (empty or not found)"
fi

if [ -d "$DOTFILES_DIR/icons" ] && [ "$(ls -A "$DOTFILES_DIR/icons" 2>/dev/null)" ]; then
  mkdir -p "$HOME/.local/share/icons"
  rsync -a "$DOTFILES_DIR/icons/" "$HOME/.local/share/icons/"
  log "Icon themes restored"
else
  skip "icons/ (empty or not found)"
fi

section "Fonts"
if [ -d "$DOTFILES_DIR/fonts" ] && [ "$(ls -A "$DOTFILES_DIR/fonts" 2>/dev/null)" ]; then
  mkdir -p "$HOME/.local/share/fonts"
  rsync -a "$DOTFILES_DIR/fonts/" "$HOME/.local/share/fonts/"
  fc-cache -fv 2>&1 | tee -a "$LOGFILE" # Rebuild font index so apps can find new fonts
  log "Fonts restored + font cache rebuilt"
else
  skip "fonts/ (empty — did you run backup.sh --fonts?)"
fi

# =============================================================================
# STEP 16 — RESTORE WALLPAPERS
#
# Wallpapers go to ~/Pictures/Wallpapers (your primary collection) and also
# to ~/.config/hypr/wallpapers (where hyprpaper looks for them by default).
# =============================================================================
section "Wallpapers"

if [ -d "$DOTFILES_DIR/wallpapers" ] && [ "$(ls -A "$DOTFILES_DIR/wallpapers" 2>/dev/null)" ]; then
  mkdir -p "$HOME/Pictures/Wallpapers"
  rsync -a "$DOTFILES_DIR/wallpapers/" "$HOME/Pictures/Wallpapers/"
  # Also copy to hyprpaper's default search location
  if [ -d "$HOME/.config/hypr" ]; then
    mkdir -p "$HOME/.config/hypr/wallpapers"
    rsync -a "$DOTFILES_DIR/wallpapers/" "$HOME/.config/hypr/wallpapers/"
  fi
  log "Wallpapers restored to ~/Pictures/Wallpapers"
else
  skip "wallpapers/ (empty — did you run backup.sh --wallpapers?)"
fi

# =============================================================================
# STEP 17 — SDDM DISPLAY MANAGER CONFIG
#
# SDDM is the login screen. HyDE sets a custom theme in /etc/sddm.conf.d/.
# Without this, the login screen will use the plain SDDM default theme.
# We also make sure SDDM is enabled as the display manager service.
# =============================================================================
section "SDDM config"

if [ -d "$DOTFILES_DIR/system/sddm.conf.d" ] && [ "$(ls -A "$DOTFILES_DIR/system/sddm.conf.d" 2>/dev/null)" ]; then
  sudo mkdir -p /etc/sddm.conf.d
  sudo rsync -a "$DOTFILES_DIR/system/sddm.conf.d/" /etc/sddm.conf.d/
  log "SDDM config restored to /etc/sddm.conf.d/"
else
  skip "system/sddm.conf.d (empty — HyDE installer sets this)"
fi

# Enable SDDM service so the login screen starts on boot
if systemctl list-unit-files sddm.service &>/dev/null; then
  sudo systemctl enable sddm 2>&1 | tee -a "$LOGFILE" || true
  log "SDDM enabled"
fi

# Restore Qylock SDDM themes to /usr/share/sddm/themes/
if [ -d "$DOTFILES_DIR/system/sddm-themes" ] && [ "$(ls -A "$DOTFILES_DIR/system/sddm-themes" 2>/dev/null)" ]; then
  sudo mkdir -p /usr/share/sddm/themes
  sudo rsync -a "$DOTFILES_DIR/system/sddm-themes/" /usr/share/sddm/themes/
  log "SDDM themes restored to /usr/share/sddm/themes/"
fi

# =============================================================================
# STEP 18 — GRUB CONFIG
#
# /etc/default/grub holds kernel parameters, timeout, and theme path.
# After restoring the file we must regenerate /boot/grub/grub.cfg —
# GRUB reads the compiled .cfg file, not the /etc/default/grub source.
# Without grub-mkconfig the new parameters won't take effect.
# =============================================================================
section "GRUB"

if [ -f "$DOTFILES_DIR/system/grub" ]; then
  sudo cp "$DOTFILES_DIR/system/grub" /etc/default/grub
  log "/etc/default/grub restored"

  if command -v grub-mkconfig &>/dev/null; then
    sudo grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | tee -a "$LOGFILE"
    log "GRUB config regenerated (/boot/grub/grub.cfg)"
  else
    warn "grub-mkconfig not found — install grub package and run manually:"
    warn "  sudo grub-mkconfig -o /boot/grub/grub.cfg"
  fi
else
  skip "system/grub (not found — default GRUB config will be used)"
fi

# =============================================================================
# STEP 19 — SYSTEM SERVICES
#
# Enable services that should start automatically on every boot.
# bluetooth and cups (printing) are optional but good to have enabled.
# Pipewire is the modern audio stack — enabled as user services, not system.
# =============================================================================
section "Enabling system services"

SERVICES=(bluetooth cups)
for svc in "${SERVICES[@]}"; do
  # Check the service exists before trying to enable it
  if systemctl list-unit-files "${svc}.service" &>/dev/null 2>&1; then
    sudo systemctl enable "$svc" 2>&1 | tee -a "$LOGFILE" || true
    log "Enabled $svc"
  fi
done

# Pipewire runs as user services (--user), not system services.
# wireplumber is the session manager that replaces pipewire-media-session.
systemctl --user enable --now pipewire pipewire-pulse wireplumber 2>&1 | tee -a "$LOGFILE" || true
log "Pipewire services enabled"

# =============================================================================
# STEP 20 — DEFAULT SHELL (ZSH)
#
# chsh changes the login shell in /etc/passwd. We only do this if:
#   1. A .zshrc exists (meaning we actually want zsh)
#   2. zsh is installed
#   3. The current shell isn't already zsh
# =============================================================================
section "Default shell"

if [ -f "$HOME/.zshrc" ] && command -v zsh &>/dev/null; then
  CURRENT_SHELL=$(getent passwd "$USER" | cut -d: -f7)
  if [[ "$CURRENT_SHELL" != *"zsh"* ]]; then
    chsh -s "$(command -v zsh)" "$USER"
    log "Default shell set to zsh"
  else
    log "zsh already the default shell"
  fi
fi

# =============================================================================
# STEP 21 — HyDE RESTORE
#
# 'Hyde restore' applies the active theme from a backup tarball created by
# 'Hyde backup'. It sets the colour scheme, wallpaper, and all HyDE state
# back to exactly what it was when backup.sh was last run.
#
# The tarball lives in ~/.local/share/hyde/backups/ which was restored in
# step 14. We find the most recent one and pass it to 'Hyde restore'.
# =============================================================================
section "HyDE restore"

if command -v Hyde &>/dev/null || command -v hyde &>/dev/null; then
  CMD=$(command -v Hyde 2>/dev/null || command -v hyde)
  HYDE_BACKUP_DIR="$HOME/.local/share/hyde/backups"
  # Sort by name (tarballs are timestamped) and pick the most recent
  LATEST_BACKUP=$(find "$HYDE_BACKUP_DIR" -name "*.tar.gz" 2>/dev/null | sort | tail -1)

  if [ -n "$LATEST_BACKUP" ]; then
    log "Restoring HyDE from $(basename "$LATEST_BACKUP")..."
    "$CMD" restore "$(basename "${LATEST_BACKUP%.tar.gz}")" 2>&1 | tee -a "$LOGFILE" ||
      warn "Hyde restore returned non-zero — check themes manually"
    log "HyDE themes + wallpaper state restored"
  else
    warn "No Hyde backup tarball found in $HYDE_BACKUP_DIR"
    warn "Apply a theme manually after reboot with: Hyde theme <n>"
  fi
else
  warn "Hyde CLI not available — run 'Hyde restore' manually after reboot"
fi

# =============================================================================
# ALL DONE
# =============================================================================
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗"
echo -e "║           Setup complete!  🎉            ║"
echo -e "╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Full log : ${CYAN}$LOGFILE${NC}"
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo -e "  1. Review $LOGFILE for any warnings"
echo -e "  2. ${YELLOW}Reboot${NC}"
echo -e "  3. Select Hyprland at the SDDM login screen"
echo -e "  4. If themes look off: run ${CYAN}Hyde restore${NC}"
echo ""
