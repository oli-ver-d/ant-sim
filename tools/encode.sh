#!/usr/bin/env bash
# Encodes a Movie Maker PNG sequence (frame00000000.png, ...) to an MP4 that
# TikTok / Reels accept: H.264, yuv420p, CRF 18, 60 fps, no audio, faststart.
# Deletes the frames afterwards unless KEEP_FRAMES=1.
#
#   tools/encode.sh <frames_dir> <out.mp4> [fps]
set -euo pipefail
frames_dir="${1:?usage: tools/encode.sh <frames_dir> <out.mp4> [fps]}"
out="${2:?usage: tools/encode.sh <frames_dir> <out.mp4> [fps]}"
fps="${3:-60}"

count=$(ls "$frames_dir"/frame*.png 2>/dev/null | wc -l)
[ "$count" -gt 0 ] || { echo "No frames in $frames_dir" >&2; exit 1; }
echo "Encoding $count frames -> $out"

ffmpeg -hide_banner -loglevel warning -stats -y \
	-framerate "$fps" -i "$frames_dir/frame%08d.png" \
	-c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
	-movflags +faststart -an \
	"$out"

if [ "${KEEP_FRAMES:-0}" != "1" ]; then
	rm -rf "$frames_dir"
fi
echo "Wrote $out"
