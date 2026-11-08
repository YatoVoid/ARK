# Sends every command typed in this shell to the journal for tools/ark-watch.
# Load it with: source tools/hooks/ark-shell.zsh
autoload -Uz add-zsh-hook
__ark_log() { logger -t ark-shell -- "$1" }
add-zsh-hook preexec __ark_log
