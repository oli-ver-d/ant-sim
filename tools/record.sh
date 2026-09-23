#!/usr/bin/env bash
# Records a scenario to an H.264 MP4 in renders/.
#
#   tools/record.sh <scenario> [seed] [duration_seconds]
#   FORMAT=avi tools/record.sh <scenario> ...      # fast MJPEG capture for drafts
#
# Runs res://scenes/record.tscn under Godot's Movie Maker at a fixed 60 fps
# (so the video is perfectly smooth however slow the simulation is), then
# calls tools/encode.sh. Output: renders/<scenario>_seed<N>_<timestamp>.mp4
#
# FORMAT:
#   png (default)  lossless PNG frames; best quality, ~0.7 s per frame to write
#   avi            MJPEG at MJPEG_QUALITY (default 1.0); ~7x faster overall,
#                  very slightly softer, larger final MP4
#
# Movie Maker records at the window size chosen at startup, so a temporary
# override.cfg sets the window to 1080x1920 for this run only.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
FORMAT="${FORMAT:-png}"
MJPEG_QUALITY="${MJPEG_QUALITY:-1.0}"

scenario="${1:?usage: tools/record.sh <scenario> [seed] [duration_seconds]}"
seed="${2:--1}"
duration="${3:-}"
scenario_file="scenarios/${scenario}.json"
[ -f "$scenario_file" ] || { echo "No such scenario: $scenario_file" >&2; exit 1; }
case "$FORMAT" in
	png|avi) ;;
	*) echo "FORMAT must be png or avi (got '$FORMAT')" >&2; exit 1 ;;
esac

# The seed shown in the file name: the override, or the scenario's own.
seed_label="$seed"
if [ "$seed" -lt 0 ]; then
	seed_label="$(sed -n 's/.*"seed": *\([0-9]*\).*/\1/p' "$scenario_file" | head -1)"
fi
name="${scenario}_seed${seed_label}_$(date +%Y%m%d_%H%M%S)"
capture_dir="renders/capture_${name}"
mkdir -p "$capture_dir"

# Temporary full-size window (and MJPEG quality) for Movie Maker; always removed afterwards.
if [ -e override.cfg ]; then
	echo "override.cfg already exists; refusing to overwrite it" >&2
	exit 1
fi
trap 'rm -f override.cfg' EXIT
printf '[display]\n\nwindow/size/window_width_override=1080\nwindow/size/window_height_override=1920\n\n[editor]\n\nmovie_writer/mjpeg_quality=%s\n' "$MJPEG_QUALITY" > override.cfg

if [ "$FORMAT" = "avi" ]; then
	capture="$capture_dir/capture.avi"
else
	capture="$capture_dir/frame.png"
fi
capture_native="$capture"
if command -v cygpath >/dev/null; then capture_native="$(cygpath -w "$capture")"; fi

args=(--scenario="$scenario" --seed="$seed")
[ -n "$duration" ] && args+=(--duration="$duration")

echo "Recording $scenario ($FORMAT) -> $capture_dir"
"$GODOT" --path . --write-movie "$capture_native" --fixed-fps 60 res://scenes/record.tscn -- "${args[@]}"
rm -f override.cfg

if [ "$FORMAT" = "avi" ]; then
	tools/encode.sh "$capture" "renders/${name}.mp4"
	[ "${KEEP_FRAMES:-0}" = "1" ] || rm -rf "$capture_dir"
else
	tools/encode.sh "$capture_dir" "renders/${name}.mp4"
fi
