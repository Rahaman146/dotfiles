# ~/.local/bin/vault_toggle.sh
#!/usr/bin/env bash

mkdir -p "$HOME/.vault/.data" "$HOME/vault"

if mountpoint -q "$HOME/vault"; then
  if fuser -m "$HOME/vault" >/dev/null 2>&1; then
    zenity --question \
      --title="Vault" \
      --text="⚠️ Vault is in use.\nForce close and lock?" \
      --ok-label="Lock" \
      --cancel-label="Cancel" 2>/dev/null || exit
    fuser -km "$HOME/vault" 2>/dev/null
    sleep 0.5
  fi
  fusermount -u "$HOME/vault" && chmod 000 "$HOME/vault"
  notify-send "Vault" "🔒 Locked"
else
  PASSWORD=$(zenity --password --title="🔐 Unlock Vault")
  [ -z "$PASSWORD" ] && exit

  chmod 700 "$HOME/vault"

  if echo "$PASSWORD" | gocryptfs -passfile /dev/stdin "$HOME/.vault/.data" "$HOME/vault"; then
    notify-send "Vault" "🔓 Unlocked"
    kitty --working-directory ~/vault &
  else
    chmod 000 "$HOME/vault"
    notify-send "Vault" "❌ Wrong password"
  fi
fi
