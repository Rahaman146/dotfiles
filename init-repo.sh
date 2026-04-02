#!/usr/bin/env bash
# =============================================================================
#  init-repo.sh — ONE-TIME script to initialise the git repo and push it.
#
#  Run this ONCE on your current machine after you've placed all four scripts
#  in your dotfiles directory. It will:
#    1. Ask for your GitHub/GitLab repo URL
#    2. Ask whether to include wallpapers and fonts (they're large)
#    3. Run backup.sh to snapshot your current machine into the repo
#    4. git init → git add → git commit → git push
#
#  Prerequisites:
#    • Create an EMPTY repo on GitHub/GitLab first (no README, no files)
#    • Have your SSH key added to GitHub (or use HTTPS with a token)
#    • Run from inside your dotfiles directory
#
#  After this, future updates are just:
#    ./backup.sh --all && git add -A && git commit -m "..." && git push
# =============================================================================

set -euo pipefail

CYAN='\033[0;36m'; GREEN='\033[0;32m'; BOLD='\033[1m'; NC='\033[0m'

echo -e "\n${BOLD}╔══════════════════════════════════════════╗"
echo -e "║       HyDE Dotfiles — Init Repo          ║"
echo -e "╚══════════════════════════════════════════╝${NC}\n"

# Always resolve relative to the script location, not the caller's cwd
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Remote URL ────────────────────────────────────────────────────────────────
# SSH format (recommended): git@github.com:username/dotfiles.git
# HTTPS format:             https://github.com/username/dotfiles.git
read -rp "  GitHub/GitLab repo URL (e.g. git@github.com:you/dotfiles.git): " REMOTE_URL
echo ""

# ── Backup scope ──────────────────────────────────────────────────────────────
# Fonts (~60 MB) and wallpapers (~400 MB) are opt-in.
# Everything else (configs, packages, shell, system) is always included.
read -rp "  Include wallpapers? (can be large) [y/N]: " INC_WALLS
read -rp "  Include fonts?      (can be large) [y/N]: " INC_FONTS
echo ""

BACKUP_FLAGS=""
[[ "${INC_WALLS,,}" == "y" ]] && BACKUP_FLAGS="$BACKUP_FLAGS --wallpapers"
[[ "${INC_FONTS,,}" == "y" ]] && BACKUP_FLAGS="$BACKUP_FLAGS --fonts"

# ── Run backup ────────────────────────────────────────────────────────────────
echo -e "${CYAN}▶ Running backup.sh${NC} $BACKUP_FLAGS\n"
# shellcheck disable=SC2086  # word splitting on BACKUP_FLAGS is intentional
bash "$DOTFILES_DIR/backup.sh" $BACKUP_FLAGS

# ── Git init + first commit ───────────────────────────────────────────────────
echo -e "\n${CYAN}▶ Initialising git repo${NC}"
cd "$DOTFILES_DIR"

git init -b main                      # Initialise with 'main' as the default branch
git add -A                            # Stage everything (respects .gitignore)
git commit -m "chore: initial dotfiles snapshot ($(date '+%Y-%m-%d'))"
git remote add origin "$REMOTE_URL"
git push -u origin main               # -u sets upstream so future 'git push' works without args

echo -e "\n${GREEN}${BOLD}✔ Done! Repo pushed to ${CYAN}$REMOTE_URL${NC}"
echo ""
echo -e "  On your next machine, run:"
echo -e "    ${CYAN}git clone $REMOTE_URL ~/dotfiles${NC}"
echo -e "    ${CYAN}cd ~/dotfiles && chmod +x setup.sh && ./setup.sh${NC}\n"
