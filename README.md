# 🏔️ HyDE + Arch Dotfiles

My personal Arch Linux setup with [HyDE](https://github.com/HyDE-Project/HyDE). Clone this repo and run `setup.sh` on a fresh Arch install to get the exact same environment.

---

## 📁 Repo Structure

```
dotfiles/
├── setup.sh                   ← Run on a FRESH Arch install
├── backup.sh                  ← Run on CURRENT machine to update repo
├── init-repo.sh               ← One-time: create git repo + first push
│
├── packages/
│   ├── pacman.txt             ← Explicitly installed native packages
│   ├── aur.txt                ← AUR + chaotic-aur packages
│   ├── codium-extensions.txt  ← VSCodium / Code-OSS extensions
│   └── pipx.txt               ← Global pipx tools
│
├── configs/                   ← Mirrors ~/.config/
│   ├── hypr/                  ← Hyprland (keybinds, rules, monitors)
│   ├── hyde/                  ← HyDE theming engine
│   ├── waybar/                ← Status bar
│   ├── rofi/                  ← App launcher
│   ├── kitty/                 ← Terminal
│   ├── _files/                ← Single-file configs (mimeapps.list etc.)
│   └── ...
│
├── shell/                     ← Home dotfiles
│   ├── .zshrc / .zshenv       ← Zsh config
│   ├── .gitconfig             ← Git identity + aliases
│   └── ssh/config             ← SSH host aliases (NO private keys)
│
├── local_bin/                 ← ~/.local/bin custom scripts
├── local_share/               ← ~/.local/share HyDE data + .desktop files
│   ├── applications/          ← Custom .desktop launchers
│   ├── hyde/                  ← HyDE internal data + backup tarballs
│   ├── wallbash/              ← HyDE wallbash colour engine
│   └── ...
│
├── themes/                    ← ~/.local/share/themes (GTK themes)
├── icons/                     ← ~/.local/share/icons (icon packs)
├── fonts/                     ← ~/.local/share/fonts (opt-in)
├── wallpapers/                ← Wallpapers (opt-in)
│
└── system/                    ← /etc snapshots
    ├── pacman.conf            ← Custom repos, options (chaotic-aur, ILoveCandy)
    ├── grub                   ← /etc/default/grub (kernel params, theme)
    ├── sddm.conf.d/           ← SDDM display manager theme
    ├── fstab / hostname / locale.gen / ...
    └── pacman.d/
        └── chaotic-mirrorlist ← chaotic-aur mirror preferences
```

---

## 🚀 Fresh Arch Setup

### Prerequisites
1. Install Arch Linux base (follow the [Arch Wiki install guide](https://wiki.archlinux.org/title/Installation_guide))
2. Boot into your new system as a **normal user with sudo access**
3. Confirm you have an internet connection

### One-liner

```bash
git clone https://github.com/YOUR_USERNAME/dotfiles.git ~/dotfiles
cd ~/dotfiles
chmod +x setup.sh
./setup.sh
```

### What setup.sh does, in order

| Step | Action |
|------|--------|
| 1 | System update + base deps |
| 2 | Restore `/etc/pacman.conf` (custom repos, options) |
| 3 | Set up **chaotic-aur** (keyring + mirrorlist) |
| 4 | Install **yay** |
| 5 | Run the official **HyDE installer** |
| 6 | Install pacman packages |
| 7 | Install AUR packages |
| 8 | Install **VSCodium extensions** |
| 9 | Install **pipx** tools |
| 10 | Restore `~/.config` directories |
| 11 | Restore home dotfiles (`.zshrc`, `.gitconfig`, `.ssh/config`) |
| 12 | Install **oh-my-zsh** (if referenced in .zshrc) |
| 13 | Restore `~/.local/bin` scripts + `chmod +x` |
| 14 | Restore `~/.local/share` (HyDE data, wallbash, .desktop files) |
| 15 | Restore GTK themes, icon themes, fonts |
| 16 | Restore wallpapers |
| 17 | Restore **SDDM** config + enable service |
| 18 | Restore **GRUB** config + regenerate |
| 19 | Enable system services (bluetooth, cups, pipewire) |
| 20 | Set zsh as default shell |
| 21 | Run **Hyde restore** (themes + wallpaper state) |

### Flags

| Flag | What it does |
|------|-------------|
| `--skip-hyde` | Skip HyDE installer (if already installed) |
| `--skip-packages` | Skip all package installation |
| `--configs-only` | Only restore dotfiles and configs |

```bash
# Re-apply configs only (fast, no reinstalling)
./setup.sh --configs-only
```

---

## 💾 Updating Your Dotfiles

Run this on your current machine after making changes:

```bash
./backup.sh            # Configs, packages, shell, system
./backup.sh --fonts    # + fonts
./backup.sh --all      # + fonts AND wallpapers
```

Then push:
```bash
git add -A
git commit -m "chore: update dotfiles $(date '+%Y-%m-%d')"
git push
```

---

## 🔵 About HyDE Backup

`Hyde backup` (step 9 of backup.sh) saves HyDE's internal state:
- Active theme + colour scheme
- Wallpaper set index
- HyDE database

The tarball lands in `~/.local/share/hyde/backups/`, which is captured by `local_share/hyde/`. On restore, `setup.sh` calls `Hyde restore` with the most recent tarball to bring back your exact theme and wallpaper selection.

This is **separate** from backing up `~/.config/hyde` (raw config files). Both are needed for a perfect restore.

---

## 🔑 Secrets

**Never commit private SSH keys or tokens.** The `.ssh/config` (host aliases) is safe to commit. For private keys, tokens, and passwords, use:

- [pass](https://www.passwordstore.org/) — GPG-encrypted password store
- [age](https://github.com/FiloSottile/age) — simple file encryption
- Bitwarden CLI / 1Password CLI

After a fresh setup, restore your SSH private keys manually:
```bash
# Copy your keys to ~/.ssh/ and set permissions
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
```

---

## ⚙️ Customising

**Add a new app to backup:**
```bash
# In backup.sh, add to CONFIG_DIRS:
your-app-name    # description
```

**Exclude files from a tracked config dir:**
```bash
# Create a .gitignore inside that config folder, e.g.:
echo "secrets.conf" >> configs/hypr/.gitignore
```

**Add a new system file:**
```bash
# In backup.sh SYSTEM_FILES array:
/etc/your-file
# In setup.sh, add the corresponding restore + apply step
```

---

## 📝 Notes

- `system/` files are machine-specific snapshots. `setup.sh` applies `pacman.conf` and `grub` automatically but treats others (fstab, hostname) as reference only — apply manually if needed.
- Run `fc-cache -fv` if fonts look wrong after first boot.
- The `local_bin/uv` and `local_bin/uvx` binaries are excluded from git and reinstalled fresh via the official uv installer.
- **First boot**: if Hyprland doesn't start, check that SDDM is enabled (`sudo systemctl enable sddm`) and the `~/.config/hypr/hyprland.conf` is present.

---

## 🖼️ Screenshot

<!-- Add a screenshot of your desktop here -->
<img width="1920" height="1200" alt="image" src="https://github.com/user-attachments/assets/7d76db72-277b-4d9d-a26d-768710fc1b86" />
<img width="1920" height="1200" alt="image" src="https://github.com/user-attachments/assets/b92e8537-6ba0-456a-8d42-99b361b7d9f4" />
<img width="1920" height="1200" alt="image" src="https://github.com/user-attachments/assets/58c506ae-d73b-47e7-a1c0-837db2b4285b" />
<img width="1920" height="1200" alt="image" src="https://github.com/user-attachments/assets/fab20efb-16f6-43a8-ba88-ff91eaf5c663" />
<img width="1920" height="1200" alt="image" src="https://github.com/user-attachments/assets/9b3ab10a-cfd7-4c29-8f5b-7d7536ed34e1" />
---

*Managed by [backup.sh](./backup.sh)*
