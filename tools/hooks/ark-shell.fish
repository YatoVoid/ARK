# Sends every command typed in this shell to the journal for tools/ark-watch.
# Load it with: source tools/hooks/ark-shell.fish
function __ark_log --on-event fish_preexec
    logger -t ark-shell -- "$argv"
end
