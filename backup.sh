#!/usr/bin/env bash
# =============================================================================
#  backup.sh — Snapshot your current HyDE + Arch setup into this repo
#
#  Run this on your CURRENT machine whenever you want to save your config.
#  It is safe to run multiple times — rsync only copies what changed.
#
#  Usage:
#    ./backup.sh                 # configs, packages, shell, system
#    ./backup.sh --fonts         # + ~/.local/share/fonts  (61 MB on your system)
#    ./backup.sh --wallpapers    # + ~/Pictures/Wallpapers (408 MB)
#    ./backup.sh --all           # everything
#
#  After running, review with:
#    git diff --stat
#  Then commit and push.
# =============================================================================

# Exit immediately on error, treat unset variables as errors,
# and fail if any command in a pipe fails (not just the last one).
set -euo pipefail

# Always resolve the dotfiles dir relative to this script's location,
# so the script works regardless of where you call it from.
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_WALLPAPERS=false
BACKUP_FONTS=false

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # reset — must come after every coloured string

log() { echo -e "${GREEN}  ✔${NC}  $1"; }
section() { echo -e "\n${CYAN}${BOLD}▶ $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠${NC}  $1"; }
skip() { echo -e "     ${YELLOW}skip${NC}  $1 (not found)"; }

# ── Arg parsing ───────────────────────────────────────────────────────────────
# Fonts and wallpapers are opt-in because they are large (60MB+ and 400MB+).
# Everything else is always backed up — it's small enough to not matter.
for arg in "$@"; do
  case $arg in
  --wallpapers) BACKUP_WALLPAPERS=true ;;
  --fonts) BACKUP_FONTS=true ;;
  --all)
    BACKUP_WALLPAPERS=true
    BACKUP_FONTS=true
    ;;
  esac
done

echo -e "\n${BOLD}╔══════════════════════════════════════════╗"
echo -e "║         HyDE Dotfiles — Backup           ║"
echo -e "╚══════════════════════════════════════════╝${NC}"
echo -e "  Dotfiles dir : ${CYAN}$DOTFILES_DIR${NC}"
echo -e "  Wallpapers   : $($BACKUP_WALLPAPERS && echo "${GREEN}yes${NC}" || echo "no  (pass --wallpapers)")"
echo -e "  Fonts        : $($BACKUP_FONTS && echo "${GREEN}yes${NC}" || echo "no  (pass --fonts)")"

# =============================================================================
# 1. PACKAGE LISTS
#
# We save package names, not the packages themselves. On restore, setup.sh
# reads these lists and reinstalls everything via pacman / yay / pipx.
#
# Why separate pacman.txt and aur.txt?
#   pacman -Qqen = native packages you explicitly installed (no deps, no AUR)
#   pacman -Qqem = foreign/AUR packages (includes chaotic-aur)
# Keeping them separate lets setup.sh use the right installer for each.
# =============================================================================
section "Package lists"
mkdir -p "$DOTFILES_DIR/packages"

pacman -Qqen >"$DOTFILES_DIR/packages/pacman.txt"
log "pacman  → packages/pacman.txt ($(wc -l <"$DOTFILES_DIR/packages/pacman.txt") pkgs)"

pacman -Qqem >"$DOTFILES_DIR/packages/aur.txt"
log "AUR     → packages/aur.txt    ($(wc -l <"$DOTFILES_DIR/packages/aur.txt") pkgs)"

# VSCodium/Code-OSS extensions live outside ~/.config — they need their own
# list. setup.sh reinstalls them with: codium --install-extension <name>
if command -v codium &>/dev/null; then
  codium --list-extensions >"$DOTFILES_DIR/packages/codium-extensions.txt" 2>/dev/null
  log "codium  → packages/codium-extensions.txt ($(wc -l <"$DOTFILES_DIR/packages/codium-extensions.txt") exts)"
elif command -v code-oss &>/dev/null; then
  code-oss --list-extensions >"$DOTFILES_DIR/packages/codium-extensions.txt" 2>/dev/null
  log "code-oss → packages/codium-extensions.txt"
else
  skip "codium extensions (codium/code-oss not found)"
fi

# pipx installs Python CLI tools into isolated environments. They don't appear
# in pacman -Q, so we need a separate list. 'pipx list --short' gives just names.
if command -v pipx &>/dev/null; then
  pipx list --short 2>/dev/null | awk '{print $1}' >"$DOTFILES_DIR/packages/pipx.txt"
  log "pipx    → packages/pipx.txt ($(wc -l <"$DOTFILES_DIR/packages/pipx.txt") tools)"
else
  skip "pipx tools (pipx not installed)"
fi

# npm global packages (tools installed with npm install -g)
# tail -n +2 skips the first line which is just the global node_modules path.
if command -v npm &>/dev/null; then
  npm list -g --depth=0 --parseable 2>/dev/null | tail -n +2 | xargs -I{} basename {} \
    >"$DOTFILES_DIR/packages/npm-global.txt" 2>/dev/null || true
  [[ -s "$DOTFILES_DIR/packages/npm-global.txt" ]] &&
    log "npm     → packages/npm-global.txt" ||
    skip "npm global packages (none found)"
fi

# =============================================================================
# 2. ~/.config — DIRECTORIES AND SINGLE FILES
#
# rsync -a --delete mirrors the source exactly:
#   -a = archive mode (preserves permissions, timestamps, symlinks)
#   --delete = removes files from dest that no longer exist in source
#
# Why not just 'cp -r ~/.config'?
#   That would capture browser profiles, caches, and app data we don't want.
#   The explicit CONFIG_DIRS list gives us full control over what's tracked.
#
# The .gitignore handles a second layer of exclusion (caches, extension storage
# etc.) for anything that slips through from these directories.
# =============================================================================
section "~/.config directories"
mkdir -p "$DOTFILES_DIR/configs"

CONFIG_DIRS=(
  # ── Hyprland / HyDE (core) — the most important dirs ──────────────────────
  hypr # Hyprland WM: keybinds, window rules, monitor layout, autostart
  hyde # HyDE theming engine: theme configs, colour schemes, scripts
  uwsm # Universal Wayland Session Manager — HyDE uses this to launch

  # ── Status bar / launcher / notifications ──────────────────────────────────
  waybar  # Top/bottom bar: modules, style.css, config.jsonc
  rofi    # App launcher and switcher themes + config
  dunst   # Notification daemon appearance and behaviour
  wlogout # Logout menu button layout and style

  # ── Terminal ────────────────────────────────────────────────────────────────
  kitty # Font, opacity, keybinds, theme

  # ── Shell ───────────────────────────────────────────────────────────────────
  fish     # Fish functions, completions, config.fish, fish_variables
  zsh      # Zsh plugin config, completions, theme (e.g. oh-my-zsh extras)
  starship # Cross-shell prompt: starship.toml

  # ── Monitoring / system info ────────────────────────────────────────────────
  fastfetch # System info display layout and modules
  btop      # Resource monitor theme and layout
  htop      # htop colour and column config
  MangoHud  # In-game / app performance overlay config

  # ── Media ───────────────────────────────────────────────────────────────────
  mpv       # Video player keybinds, scripts, shaders
  cava      # Terminal audio spectrum visualiser colours + style
  spotify   # Spotify client preferences
  spicetify # Spotify UI customisation (themes, extensions, colour.ini)

  # ── GTK / Qt / Theming ──────────────────────────────────────────────────────
  gtk-3.0    # GTK3: theme name, font, icon set, cursor
  gtk-4.0    # GTK4: same but for GTK4 apps
  Kvantum    # Qt5/6 theme engine — sets the Qt visual style
  qt5ct      # Qt5 appearance: theme, font, icon theme
  qt6ct      # Qt6 appearance (same idea, separate config)
  nwg-look   # Wayland GTK settings manager (replaces lxappearance)
  wal        # pywal: generates colour schemes from wallpapers
  xsettingsd # X settings daemon for legacy X11 apps running under Wayland

  # ── Editors / Dev ───────────────────────────────────────────────────────────
  nvim         # Neovim: init.lua / lazy.nvim plugin config
  vim          # Vim: .vimrc equivalent inside ~/.config/vim
  'Code - OSS' # VS Code OSS settings, keybindings (NOT extensions — those are in packages/)
  VSCodium     # VSCodium settings + keybindings (ditto)
  yay          # yay AUR helper config (makepkg options, diff viewing etc.)

  # ── CLI / TUI tools ─────────────────────────────────────────────────────────
  activitywatch # Time tracker categories and settings
  fastanime     # Anime streaming CLI preferences and history
  flix-cli      # Movie/show streaming CLI config
  mangal        # Manga reader CLI: sources, download path
  manga-tui     # Manga TUI reader config
  viu           # Terminal image viewer config
  novel-cli     # Novel reader CLI config
  nwg-displays  # Wayland display arrangement tool config
  environment.d # User-level env vars loaded by systemd (e.g. PATH additions)
)

# These are standalone files (not directories) that live directly in ~/.config.
# Stored in configs/_files/ to keep them separate from the directory backups.
CONFIG_FILES=(
  mimeapps.list      # Which app opens which file type (xdg-open associations)
  user-dirs.dirs     # XDG paths: where Downloads, Pictures, etc. point
  user-dirs.locale   # Locale used when naming XDG dirs
  spotify-flags.conf # Spotify launch flags (e.g. --enable-features=...)
  code-flags.conf    # VS Code OSS launch flags
  codium-flags.conf  # VSCodium launch flags
  QtProject.conf     # Qt global settings shared across Qt apps
  kdeglobals         # KDE global config — read by Qt apps for fonts/icons even without KDE
  xdg-terminals.list # Preferred terminal emulator for xdg-open and file managers
  pavucontrol.ini    # PulseAudio volume control window layout
)

for dir in "${CONFIG_DIRS[@]}"; do
  src="$HOME/.config/$dir"
  if [ -d "$src" ]; then
    mkdir -p "$DOTFILES_DIR/configs/$dir"
    rsync -a --delete "$src/" "$DOTFILES_DIR/configs/$dir/"
    log "$dir"
  elif [ -f "$src" ]; then
    # Some "configs" are single files rather than directories (e.g. starship.toml)
    cp "$src" "$DOTFILES_DIR/configs/$dir"
    log "$dir (file)"
  else
    skip "~/.config/$dir"
  fi
done

mkdir -p "$DOTFILES_DIR/configs/_files"
for f in "${CONFIG_FILES[@]}"; do
  src="$HOME/.config/$f"
  if [ -f "$src" ]; then
    cp "$src" "$DOTFILES_DIR/configs/_files/$f"
    log "_files/$f"
  else
    skip "~/.config/$f"
  fi
done

# =============================================================================
# 3. HOME DOTFILES — shell configs, git identity, ssh host aliases
#
# These live in $HOME directly (not in ~/.config) so they need separate handling.
# .gitconfig and .ssh/config are called out explicitly because they're critical
# and easy to forget. Private SSH keys are NEVER copied — only the config file
# which contains host aliases and options (safe to version control).
# =============================================================================
section "Home dotfiles"
mkdir -p "$DOTFILES_DIR/shell"

HOME_DOTFILES=(
  # Zsh — the main shell. .zshenv is read even in non-interactive shells,
  # so it's the right place for PATH and critical env vars.
  .zshrc .zprofile .zshenv .zsh_aliases .zsh_functions
  # Bash — kept as fallback even if zsh is the default shell
  .bashrc .bash_profile .bash_aliases .bash_logout
  .profile # POSIX shell profile — read by many login managers
  # Misc dotfiles
  .gtkrc-2.0  # GTK2 settings — still read by some older Electron apps
  .Xresources # X11 resources — xrdb loads this; some Wayland compositors still use it
  .viminfo    # Vim command/search history and register state
)

for f in "${HOME_DOTFILES[@]}"; do
  if [ -f "$HOME/$f" ]; then
    cp "$HOME/$f" "$DOTFILES_DIR/shell/$f"
    log "$f"
  fi
done

# .gitconfig holds your name, email, default branch, aliases, gpg signing key.
# Without this, git commits on a new machine have no author identity.
if [ -f "$HOME/.gitconfig" ]; then
  cp "$HOME/.gitconfig" "$DOTFILES_DIR/shell/.gitconfig"
  log ".gitconfig"
else
  skip "~/.gitconfig"
fi

# ~/.ssh/config defines host aliases (e.g. 'github' → github.com with your key).
# ONLY the config file is backed up — private keys (id_ed25519, id_rsa etc.)
# must NEVER be committed to git. Restore keys manually from a password manager.
mkdir -p "$DOTFILES_DIR/shell/ssh"
if [ -f "$HOME/.ssh/config" ]; then
  cp "$HOME/.ssh/config" "$DOTFILES_DIR/shell/ssh/config"
  log ".ssh/config (host aliases only — private keys NOT included)"
else
  skip "~/.ssh/config"
fi

# =============================================================================
# 4. ~/.local/bin — CUSTOM SCRIPTS
#
# This is where user-installed executables and personal scripts live.
# We exclude large compiled binaries that are better reinstalled fresh:
#   copilot — 132 MB binary (GitHub rejected it; reinstall from npm/gh cli)
#   claude  — Anthropic Claude CLI binary
#   uv/uvx  — Python package manager binary (reinstalled via astral.sh installer)
#
# Everything else (hydectl, hyde-shell, vault_toggle.sh, env, env.fish) is a
# small text script and is safe + valuable to track.
# =============================================================================
section "~/.local/bin (custom scripts)"
mkdir -p "$DOTFILES_DIR/local_bin"

if [ -d "$HOME/.local/bin" ] && [ "$(ls -A "$HOME/.local/bin" 2>/dev/null)" ]; then
  rsync -a --delete \
    --exclude='uv' \
    --exclude='uvx' \
    --exclude='copilot' \
    --exclude='claude' \
    "$HOME/.local/bin/" "$DOTFILES_DIR/local_bin/"
  log "~/.local/bin → local_bin/ ($(ls "$DOTFILES_DIR/local_bin" | wc -l) scripts)"
else
  skip "~/.local/bin (empty)"
fi

# =============================================================================
# 5. ~/.local/share — HyDE DATA, .DESKTOP FILES, WALLBASH
#
# Unlike ~/.config (which holds app configuration), ~/.local/share holds
# app data — HyDE's theme database, custom .desktop launchers, wallbash
# colour templates, etc. Critical for an exact HyDE restore.
#
# We are deliberately selective here. We do NOT back up:
#   flatpak/  — reinstall apps via flatpak
#   Steam/    — too large, reinstall games separately
#   baloo/    — KDE file indexer database, auto-rebuilds
#   Trash/    — obviously not
# =============================================================================
section "~/.local/share (HyDE data + .desktop files)"
mkdir -p "$DOTFILES_DIR/local_share"

LOCAL_SHARE_DIRS=(
  # ── HyDE core — most critical, without these themes won't restore ───────────
  hyde     # HyDE internal state: active theme, colour cache, backup tarballs
  wallbash # Wallbash colour engine: templates that generate per-wallpaper schemes
  hypr     # Hyprland share data (cursor themes etc.)
  hyprland # Hyprland runtime share files

  # ── Bar / launcher / notifications ─────────────────────────────────────────
  waybar # Custom CSS modules and waybar share data
  rofi   # Rofi icon theme cache and share data

  # ── App data worth keeping ──────────────────────────────────────────────────
  applications # Custom .desktop launcher files (apps that don't install their own)
  fastfetch    # Fastfetch preset files stored in share
  novel-cli    # Novel CLI reading progress and library data
  manga-tui    # Manga TUI reading progress and library data
  zathura      # PDF viewer bookmarks and document history
  okular       # PDF viewer annotations and reading history
  cliphist     # Clipboard history (wl-clipboard history manager)
  wl-clip      # Wayland clipboard share data

  # ── KDE / Qt app data ───────────────────────────────────────────────────────
  konsole             # Konsole terminal profiles and colour schemes
  dolphin             # Dolphin file manager bookmarks and view settings
  kio                 # KDE I/O framework data (network mounts, recent files)
  kxmlgui5            # KDE GUI state for Qt5 apps (toolbar layouts etc.)
  ark                 # Ark archive manager settings and recent files
  desktop-directories # XDG desktop directory definitions (.directory files)

  # ── Misc ────────────────────────────────────────────────────────────────────
  sddm           # SDDM user-level data (last selected session, user avatar)
  resourcefullib # Shared resource library used by some HyDE components
)

for dir in "${LOCAL_SHARE_DIRS[@]}"; do
  src="$HOME/.local/share/$dir"
  if [ -d "$src" ] && [ "$(ls -A "$src" 2>/dev/null)" ]; then
    mkdir -p "$DOTFILES_DIR/local_share/$dir"
    rsync -a --delete "$src/" "$DOTFILES_DIR/local_share/$dir/"
    log "local_share/$dir"
  else
    skip "~/.local/share/$dir"
  fi
done

# =============================================================================
# 6. GTK THEMES, ICON THEMES, FONTS
#
# Themes and icons in ~/.local/share/themes and ~/.local/share/icons are user-
# installed theme packs. We back them up in dedicated top-level folders so they
# can be restored without touching the whole ~/.local/share tree.
#
# Fonts are opt-in (--fonts / --all) because they add ~60 MB to the repo.
# If all your fonts come from packages (pacman/AUR), skip this — setup.sh will
# reinstall them via pacman.txt. Only back up fonts you installed manually.
# =============================================================================
section "GTK Themes"
mkdir -p "$DOTFILES_DIR/themes"
if [ -d "$HOME/.local/share/themes" ] && [ "$(ls -A "$HOME/.local/share/themes" 2>/dev/null)" ]; then
  rsync -a --delete "$HOME/.local/share/themes/" "$DOTFILES_DIR/themes/"
  log "themes ($(ls "$HOME/.local/share/themes" | wc -l) found)"
else
  skip "~/.local/share/themes"
fi

section "Icon Themes"
mkdir -p "$DOTFILES_DIR/icons"
if [ -d "$HOME/.local/share/icons" ] && [ "$(ls -A "$HOME/.local/share/icons" 2>/dev/null)" ]; then
  rsync -a --delete "$HOME/.local/share/icons/" "$DOTFILES_DIR/icons/"
  log "icons ($(ls "$HOME/.local/share/icons" | wc -l) found)"
else
  skip "~/.local/share/icons"
fi

section "Fonts"
if $BACKUP_FONTS; then
  mkdir -p "$DOTFILES_DIR/fonts"
  if [ -d "$HOME/.local/share/fonts" ] && [ "$(ls -A "$HOME/.local/share/fonts" 2>/dev/null)" ]; then
    rsync -a --delete "$HOME/.local/share/fonts/" "$DOTFILES_DIR/fonts/"
    log "fonts ($(find "$HOME/.local/share/fonts" -type f | wc -l) files)"
  else
    skip "~/.local/share/fonts"
  fi
else
  warn "Fonts skipped — run with --fonts or --all to include."
fi

# =============================================================================
# 7. WALLPAPERS
#
# Opt-in via --wallpapers or --all. At ~408 MB they push the repo large but
# are worth including if you want a truly identical desktop on day one.
# Multiple source locations are checked since HyDE and hyprpaper each have
# their own preferred wallpaper directory.
# =============================================================================
section "Wallpapers"
if $BACKUP_WALLPAPERS; then
  mkdir -p "$DOTFILES_DIR/wallpapers"
  WALL_SOURCES=(
    "$HOME/.config/hypr/wallpapers"
    "$HOME/Pictures/Wallpapers"
    "$HOME/Pictures/wallpapers"
    "$HOME/.local/share/backgrounds"
    "$HOME/.local/share/hypr/wallpapers"
  )
  found_walls=false
  for wsrc in "${WALL_SOURCES[@]}"; do
    if [ -d "$wsrc" ] && [ "$(ls -A "$wsrc" 2>/dev/null)" ]; then
      rsync -a "$wsrc/" "$DOTFILES_DIR/wallpapers/"
      log "Wallpapers from $wsrc"
      found_walls=true
    fi
  done
  $found_walls || warn "No wallpapers found in known locations."
else
  warn "Wallpapers skipped — run with --wallpapers or --all to include."
fi

# =============================================================================
# 8. SYSTEM-LEVEL CONFIGS (/etc)
#
# These files live in /etc and require root to write on restore, but can
# usually be read without sudo. We store them as reference snapshots.
#
# setup.sh applies pacman.conf and grub automatically.
# Others (fstab, hostname, mkinitcpio.conf) are machine-specific — review
# manually before applying on a new machine.
#
# Key files explained:
#   pacman.conf        — custom repos (chaotic-aur, multilib), ILoveCandy,
#                        ParallelDownloads, DownloadUser etc.
#   grub               — kernel parameters: quiet, loglevel, amdgpu flags,
#                        resume= (for hibernate), custom GRUB_THEME path
#   mkinitcpio.conf    — initramfs hooks (needed if you use plymouth, btrfs etc.)
#   sddm.conf.d/       — SDDM display manager theme (HyDE sets this)
#   chaotic-mirrorlist — saved mirror list so setup.sh uses the same fast mirrors
# =============================================================================
section "System configs"
mkdir -p "$DOTFILES_DIR/system"
mkdir -p "$DOTFILES_DIR/system/sddm.conf.d"
mkdir -p "$DOTFILES_DIR/system/pacman.d"

SYSTEM_FILES=(
  /etc/locale.gen      # Locale definitions to generate
  /etc/locale.conf     # Active locale (LANG=en_US.UTF-8 etc.)
  /etc/vconsole.conf   # TTY keymap and font
  /etc/hostname        # Machine hostname
  /etc/hosts           # Static hostname → IP mappings
  /etc/fstab           # Filesystem mount table (machine-specific — review before applying)
  /etc/mkinitcpio.conf # Initramfs hooks and modules
  /etc/pacman.conf     # Repos, options, parallel downloads
  /etc/default/grub    # GRUB_CMDLINE_LINUX_DEFAULT, theme, timeout etc.
)

for f in "${SYSTEM_FILES[@]}"; do
  fname=$(basename "$f")
  if [ -f "$f" ]; then
    cp "$f" "$DOTFILES_DIR/system/$fname" 2>/dev/null ||
      warn "Could not read $f (try running with sudo)"
    log "system/$fname"
  else
    skip "$f"
  fi
done

# SDDM config.d — HyDE writes its login screen theme config here.
# Without this the display manager will use the plain default theme.
if [ -d /etc/sddm.conf.d ] && [ "$(ls -A /etc/sddm.conf.d 2>/dev/null)" ]; then
  rsync -a /etc/sddm.conf.d/ "$DOTFILES_DIR/system/sddm.conf.d/" 2>/dev/null ||
    warn "/etc/sddm.conf.d — permission denied (try sudo)"
  log "system/sddm.conf.d/"
else
  skip "/etc/sddm.conf.d (empty or missing)"
fi

# Save our chaotic-aur mirror preferences so setup.sh can restore them,
# giving the new machine the same fast mirrors instead of a random default.
if [ -f /etc/pacman.d/chaotic-mirrorlist ]; then
  cp /etc/pacman.d/chaotic-mirrorlist "$DOTFILES_DIR/system/pacman.d/chaotic-mirrorlist" 2>/dev/null || true
  log "system/pacman.d/chaotic-mirrorlist"
fi

# Qylock SDDM themes (manually installed — not a pacman package)
if [ -d /usr/share/sddm/themes ] && [ "$(ls -A /usr/share/sddm/themes 2>/dev/null)" ]; then
  mkdir -p "$DOTFILES_DIR/system/sddm-themes"
  sudo rsync -a /usr/share/sddm/themes/ "$DOTFILES_DIR/system/sddm-themes/"
  log "system/sddm-themes/ ($(ls /usr/share/sddm/themes | wc -l) themes)"
fi

# =============================================================================
# 9. HyDE INTERNAL BACKUP
#
# Hyde's own backup command ('Hyde backup') saves:
#   • Active theme name + colour scheme
#   • Wallpaper set index (which wallpapers are in which theme slot)
#   • Hyde database
# It creates a timestamped tarball in ~/.local/share/hyde/backups/.
#
# We run it BEFORE the local_share rsync (step 5 above) so the tarball is
# fresh when we capture it. On restore, setup.sh finds this tarball and runs
# 'Hyde restore <name>' to put the active theme back exactly.
#
# If the Hyde CLI isn't found, it's not critical — the raw config dirs
# (configs/hyde + local_share/hyde) still give setup.sh enough to work with.
# You would just need to manually select a theme after first boot.
# =============================================================================
section "HyDE internal backup"

if command -v Hyde &>/dev/null; then
  log "Running 'Hyde backup' to snapshot active theme + wallpaper state..."
  Hyde backup 2>&1 || warn "Hyde backup returned non-zero — continuing anyway"
  log "Hyde backup complete (tarball saved to ~/.local/share/hyde/backups/)"
elif command -v hyde &>/dev/null; then
  hyde backup 2>&1 || warn "hyde backup returned non-zero — continuing"
  log "Hyde backup complete"
else
  warn "Hyde CLI not found — skipping Hyde backup."
  warn "  configs/hyde and local_share/hyde are still fully backed up."
  warn "  On restore, apply a theme manually with: Hyde theme <n>"
fi

# =============================================================================
# Done — remind the user what to do next
# =============================================================================
echo -e "\n${GREEN}${BOLD}✔ Backup complete!${NC}"
echo -e "  Review changes : ${CYAN}git -C \"$DOTFILES_DIR\" diff --stat${NC}"
echo -e "  Commit & push  :"
echo -e "    ${CYAN}cd \"$DOTFILES_DIR\" && git add -A && git commit -m 'chore: update dotfiles' && git push${NC}\n"
