#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  MRU workspace daemon for Hyprland.
#
#  Hyprland does NOT expose a workspace focus history, so we keep
#  one ourselves: subscribe to the event socket and maintain a
#  most-recently-used stack of workspace ids (front = most recent).
#
#  Every workspace change bubbles that workspace to the front —
#  EXCEPT while you are mid-switch (Alt held), when the stack is
#  frozen. That freeze is the Firefox trick: the workspace you
#  preview while holding Alt does not reorder anything until you
#  settle.
#
#  "Settle" is detected two ways, whichever comes first:
#    1. mru-ws-switch.sh commit  (bound to Alt release), or
#    2. $SETTLE seconds with no further workspace change.
#  #2 is a safety net: `bindr` on a modifier release is unreliable
#  on some setups, and without it the stack would freeze forever.
#
#  Start it once per session (see alt-tab.conf: exec-once).
# ─────────────────────────────────────────────────────────────
set -uo pipefail

source "$(dirname "$(readlink -f "$0")")/config.sh"

# Seconds of silence after a switch before we auto-commit + unfreeze.
# Defined in config.sh; fall back to 0.6 if missing.
: "${SETTLE:=0.6}"

log() { [ "${DEBUG:-0}" = 1 ] && echo "$(date '+%H:%M:%S.%3N') daemon: $*" >> "$STATE_DIR/log"; }

# Move workspace id $1 to the front of the stack (dedup), atomically.
promote() {
    local id="$1"
    [ -n "$id" ] || return 0
    [ "$IGNORE_SPECIAL" = 1 ] && (( id < 0 )) && return 0
    (
        flock 9
        { echo "$id"; grep -vxF "$id" "$STACK_FILE" 2>/dev/null; } > "$STACK_FILE.tmp"
        mv "$STACK_FILE.tmp" "$STACK_FILE"
    ) 9>"$LOCK_FILE"
}

# Drop workspace id $1 from the stack (workspace destroyed).
forget() {
    local id="$1"
    [ -n "$id" ] || return 0
    (
        flock 9
        grep -vxF "$id" "$STACK_FILE" > "$STACK_FILE.tmp" 2>/dev/null
        mv "$STACK_FILE.tmp" "$STACK_FILE"
    ) 9>"$LOCK_FILE"
}

# Seed with existing workspaces (current one first) so Alt-Tab works
# immediately, before you've switched anything this session.
seed() {
    local cur
    cur=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id')
    hyprctl workspaces -j 2>/dev/null | jq -r --argjson skip "${IGNORE_SPECIAL:-1}" '
        sort_by(.id) | .[]
        | select(($skip == 1 and .id < 0) | not)
        | .id
    ' > "$STACK_FILE"
    promote "$cur"
}

rm -f "$SWITCH_FILE"
seed

sock="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

socat -U - "UNIX-CONNECT:$sock" | while :; do
    if IFS= read -r -t "$SETTLE" line; then
        event="${line%%>>*}"
        data="${line#*>>}"
        case "$event" in
            workspacev2)
                # Frozen while a switch is in progress → don't reshuffle.
                [ -e "$SWITCH_FILE" ] && continue
                promote "${data%%,*}"      # data is "ID,NAME"
                ;;
            destroyworkspacev2)
                forget "${data%%,*}"
                ;;
        esac
    else
        # read returned false: timeout (rc>128) or socket closed (EOF).
        (( $? <= 128 )) && break          # socat died → exit daemon
        # Timed out with no events. If a switch went quiet, commit it.
        if [ -e "$SWITCH_FILE" ]; then
            cur=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id')
            rm -f "$SWITCH_FILE"
            promote "$cur"
            log "settle-commit $cur"
        fi
    fi
done
