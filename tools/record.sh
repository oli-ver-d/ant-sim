#!/usr/bin/env bash
# Records a scenario to an H.264 MP4 in renders/.
#
#   tools/record.sh <scenario | path.json> [seed] [duration_seconds]
#   FORMAT=avi tools/record.sh <scenario> ...      # fast MJPEG capture for drafts
#   CAPTIONS=0 tools/record.sh <scenario> ...      # without the scenario's captions
#   SIZE=1920x1080 tools/record.sh <scenario> ...  # another output frame size
#   START=30 tools/record.sh <scenario> 7 10       # video 30 s to 40 s
#   OUT=draft.mp4 OUT_DIR=renders/drafts tools/record.sh <scenario> ...
#
# A thin wrapper around the GDScript pipeline tools/record.gd (the same one
# the scenario editor's Record dialog runs; see its header for all options).
# The frame size is SIZE, else the scenario's "output": {"size": [w, h]}, else
# 1080x1920. Output: renders/<scenario>_seed<N>[_WxH][_nocaptions]_<time>.mp4
#
# FORMAT:
#   png (default)  lossless PNG frames; best quality, ~0.7 s per frame to write
#   avi            MJPEG at MJPEG_QUALITY (default 1.0); ~7x faster overall,
#                  very slightly softer, larger final MP4
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"

scenario="${1:?usage: tools/record.sh <scenario | path.json> [seed] [duration_seconds]}"
args=("$scenario" "${2:--1}" "${3:-}"
	--format="${FORMAT:-png}" --quality="${MJPEG_QUALITY:-1.0}" --captions="${CAPTIONS:-1}"
	--start="${START:-0}" --out_dir="${OUT_DIR:-renders}" --keep_frames="${KEEP_FRAMES:-0}")
[ -n "${SIZE:-}" ] && args+=(--size="$SIZE")
[ -n "${OUT:-}" ] && args+=(--out="$OUT")
[ -n "${FFMPEG:-}" ] && args+=(--ffmpeg="$FFMPEG")
exec "$GODOT" --headless --path . -s res://tools/record.gd -- "${args[@]}"
