#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  Shared paths / tunables for the MRU workspace switcher.
#  Sourced by mru-ws-daemon.sh and mru-ws-switch.sh.
# ─────────────────────────────────────────────────────────────

STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hypr-mru"
STACK_FILE="$STATE_DIR/stack"       # MRU list of workspace ids, front = most recent
SWITCH_FILE="$STATE_DIR/switching"  # exists only while Alt is held; holds current index
LOCK_FILE="$STATE_DIR/lock"         # flock guard: daemon + switcher must not race

# 1 = ignore scratchpad / special workspaces (they have a negative id).
IGNORE_SPECIAL=1

# Which submap to return to when a switch ends. On vanilla Hyprland your
# binds live in the root map, so this is "reset". But some dotfiles keep
# every bind inside a NAMED submap that is always active -- e.g. end-4 /
# illogical-impulse use one called "global" -- and then you must return to
# THAT, or all your keys go dead after the first Alt-Tab.
# Find yours with:  hyprctl binds -j | jq -r '.[].submap' | sort -u
RETURN_SUBMAP=reset

# FAILSAFE ONLY. Normally the choice is committed the instant you release
# the modifier (see the submap in alt-tab.conf). This is a backstop: if a
# release event is ever missed, the daemon auto-commits + unfreezes after
# this many seconds of silence so the stack can never freeze forever.
# Kept long so it never interferes with real switching.
SETTLE=3

# 1 = write every switcher call to $STATE_DIR/log (to debug whether the
#     keybind actually fires). 0 = off.
DEBUG=0

mkdir -p "$STATE_DIR"
