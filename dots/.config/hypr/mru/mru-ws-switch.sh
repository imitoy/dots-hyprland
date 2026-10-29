#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  MRU workspace switcher — the thing your keybinds call.
#
#    mru-ws-switch.sh next     step to the next (older) workspace
#    mru-ws-switch.sh prev     step back toward the most recent
#    mru-ws-switch.sh commit   finish switching (call on Alt release)
#
#  While switching, an index is kept in $SWITCH_FILE and the daemon
#  freezes the stack, so repeated `next` walks strictly down the MRU
#  order. `commit` bubbles whatever workspace you landed on to the
#  front — the only moment the order changes during a switch.
# ─────────────────────────────────────────────────────────────
set -uo pipefail

source "$(dirname "$(readlink -f "$0")")/config.sh"

[ "${DEBUG:-0}" = 1 ] && echo "$(date '+%H:%M:%S.%3N') ${1:-next}" >> "$STATE_DIR/log"

goto() {
    local id="$1"
    [ -n "$id" ] || return 0
    # Hyprland 0.55+: hyprctl dispatch 只接受 Lua 风格 dispatcher
    hyprctl dispatch "hl.dsp.focus({workspace = $id})" >/dev/null
}

case "${1:-next}" in
    next|prev)
        (
            flock 9
            mapfile -t stack < "$STACK_FILE" 2>/dev/null
            n=${#stack[@]}
            (( n < 2 )) && exit 0

            if [ -e "$SWITCH_FILE" ]; then
                idx=$(<"$SWITCH_FILE")
            else
                idx=0   # 0 == the workspace we're on right now
            fi

            if [ "$1" = next ]; then
                idx=$(( (idx + 1) % n ))
            else
                idx=$(( (idx - 1 + n) % n ))
            fi

            echo "$idx" > "$SWITCH_FILE"
            goto "${stack[$idx]}"
        ) 9>"$LOCK_FILE"
        ;;

    commit)
        # Leave the capture submap (see alt-tab.conf). Done here rather than
        # with a second bindrt line because only one bindrt per key fires.
        # Return to RETURN_SUBMAP, not necessarily root — see config.sh.
        if [ "${RETURN_SUBMAP:-reset}" = reset ]; then
            hyprctl dispatch 'hl.dsp.submap("reset")' >/dev/null
        else
            hyprctl dispatch "hl.dsp.submap(\"$RETURN_SUBMAP\")" >/dev/null
        fi
        [ -e "$SWITCH_FILE" ] || exit 0
        rm -f "$SWITCH_FILE"
        cur=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id')
        [ -n "$cur" ] || exit 0
        (
            flock 9
            { echo "$cur"; grep -vxF "$cur" "$STACK_FILE" 2>/dev/null; } > "$STACK_FILE.tmp"
            mv "$STACK_FILE.tmp" "$STACK_FILE"
        ) 9>"$LOCK_FILE"
        ;;
esac
