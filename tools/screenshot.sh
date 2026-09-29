#!/usr/bin/env bash
# Runs a scenario for N ticks (as fast as possible) and saves a PNG of the
# first rendered frame. Needs a real window: headless Godot can't render.
#   tools/screenshot.sh <scenario> <ticks> <out.png> [seed] [--zoom=3 --center=x,y] [--layout=split]
#   SIZE=1920x1080 tools/screenshot.sh ...   # another output frame (or --size=1920x1080)
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
scenario="${1:?scenario}"
ticks="${2:?ticks}"
out="$(realpath -m "${3:?out.png}")"
seed="${4:--1}"
mkdir -p "$(dirname "$out")"
# Godot on Windows needs a native path.
if command -v cygpath >/dev/null; then out="$(cygpath -w "$out")"; fi
shift 4 2>/dev/null || shift $#
# Any further arguments are passed to the main scene (e.g. --zoom=3 --center=600,700,
# --layout=split, --safe=1).
# SIZE=WxH plays in that output frame instead of the scenario's output.size
# (the PNG is the window: half the frame, or less to fit the screen).
[ -n "${SIZE:-}" ] && set -- --size="$SIZE" "$@"
"$GODOT" --path . -- --scenario="$scenario" --ticks="$ticks" --seed="$seed" --screenshot="$out" "$@"
