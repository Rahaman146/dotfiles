#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'

kitty_nvim() {
  local socket="$KITTY_LISTEN_ON"
  kitty @ --to "$socket" set-spacing padding=0
  command nvim "$@"
  kitty @ --to "$socket" set-spacing padding=default
}
alias nvim=kitty_nvim

PS1='[\u@\h \W]\$ '

. "$HOME/.local/share/../bin/env"
