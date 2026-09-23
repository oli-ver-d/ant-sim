#!/usr/bin/env bash
# Encodes a Movie Maker capture to an MP4 that TikTok / Reels accept:
# H.264, yuv420p (TV range), CRF 18, no audio, faststart.
#
#   tools/encode.sh <frames_dir | capture.avi> <out.mp4> [fps]
#
# Input is either a PNG sequence directory (frame00000000.png, ...) or an
# MJPEG .avi. MJPEG is full-range ("JPEG") colour; it's converted to TV range
# explicitly, otherwise the MP4 is tagged yuvj420p and some players / TikTok
# shift the colours. The input is deleted afterwards unless KEEP_FRAMES=1.
set -euo pipefail
input="${1:?usage: tools/encode.sh <frames_dir | capture.avi> <out.mp4> [fps]}"
out="${2:?usage: tools/encode.sh <frames_dir | capture.avi> <out.mp4> [fps]}"
fps="${3:-60}"

if [ -d "$input" ]; then
	count=$(ls "$input"/frame*.png 2>/dev/null | wc -l)
	[ "$count" -gt 0 ] || { echo "No frames in $input" >&2; exit 1; }
	echo "Encoding $count PNG frames -> $out"
	source_args=(-framerate "$fps" -i "$input/frame%08d.png")
	filter="format=yuv420p"
elif [ -f "$input" ]; then
	echo "Encoding $input -> $out"
	source_args=(-i "$input")
	filter="scale=in_range=pc:out_range=tv,format=yuv420p"
else
	echo "No such input: $input" >&2
	exit 1
fi

ffmpeg -hide_banner -loglevel warning -stats -y \
	"${source_args[@]}" \
	-vf "$filter" -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -color_range tv \
	-movflags +faststart -an \
	"$out"

if [ "${KEEP_FRAMES:-0}" != "1" ]; then
	rm -rf "$input"
fi
echo "Wrote $out"
