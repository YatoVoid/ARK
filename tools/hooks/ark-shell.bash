# Sends every command typed in this shell to the journal for tools/ark-watch.
# Load it with: source tools/hooks/ark-shell.bash
__ark_log() {
  local c
  c=$(HISTTIMEFORMAT= history 1 | sed 's/^ *[0-9]* *//')
  [ -n "$c" ] && [ "$c" != "${__ark_last-}" ] && logger -t ark-shell -- "$c"
  __ark_last=$c
}
PROMPT_COMMAND="__ark_log${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
