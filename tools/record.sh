#!/usr/bin/env bash
# Records a scenario to an H.264 MP4 in renders/.
#
#   tools/record.sh <scenario> [seed] [duration_seconds]
#
# Runs res://scenes/record.tscn under Godot's Movie Maker at a fixed 60 fps
# (PNG frames, so the video is perfectly smooth however slow the simulation
# is), then calls tools/encode.sh. Output: renders/<scenario>_seed<N>_<timestamp>.mp4
#
# Movie Maker records at the window size chosen at startup, so a temporary
# override.cfg sets the window to 1080x1920 for this run only.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"

scenario="${1:?usage: tools/record.sh <scenario> [seed] [duration_seconds]}"
seed="${2:--1}"
duration="${3:-}"
scenario_file="scenarios/${scenario}.json"
[ -f "$scenario_file" ] || { echo "No such scenario: $scenario_file" >&2; exit 1; }

# The seed shown in the file name: the override, or the scenario's own.
seed_label="$seed"
if [ "$seed" -lt 0 ]; then
	seed_label="$(sed -n 's/.*"seed": *\([0-9]*\).*/\1/p' "$scenario_file" | head -1)"
fi
name="${scenario}_seed${seed_label}_$(date +%Y%m%d_%H%M%S)"
frames_dir="renders/frames_${name}"
mkdir -p "$frames_dir"

# Temporary full-size window for Movie Maker; always removed afterwards.
if [ -e override.cfg ]; then
	echo "override.cfg already exists; refusing to overwrite it" >&2
	exit 1
fi
trap 'rm -f override.cfg' EXIT
printf '[display]\n\nwindow/size/window_width_override=1080\nwindow/size/window_height_override=1920\n' > override.cfg

frames_path="$frames_dir/frame.png"
if command -v cygpath >/dev/null; then frames_path="$(cygpath -w "$frames_path")"; fi

args=(--scenario="$scenario" --seed="$seed")
[ -n "$duration" ] && args+=(--duration="$duration")

echo "Recording $scenario -> $frames_dir"
"$GODOT" --path . --write-movie "$frames_path" --fixed-fps 60 res://scenes/record.tscn -- "${args[@]}"
rm -f override.cfg

tools/encode.sh "$frames_dir" "renders/${name}.mp4"
