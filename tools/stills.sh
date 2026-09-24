#!/usr/bin/env bash
# Full-resolution (1080x1920) stills of a scenario, for checking how it looks
# at given video times without recording the whole video.
#
#   tools/stills.sh <scenario> <times> [out_dir] [extra args...]
#   tools/stills.sh colony_founding 10,35,70 renders/stills
#
# Runs res://scenes/record.tscn under Movie Maker with --stills (see
# scenes/record.gd): per time, the scenario's layout, the nest full screen and
# a close-up of the latest digging face, as numbered PNGs in out_dir.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
scenario="${1:?usage: tools/stills.sh <scenario> <times> [out_dir]}"
times="${2:?times, e.g. 10,35,70}"
out="${3:-renders/stills_${scenario}_$(date +%Y%m%d_%H%M%S)}"
shift 3 2>/dev/null || shift $#
mkdir -p "$out"
if [ -e override.cfg ]; then
	echo "override.cfg already exists; refusing to overwrite it" >&2
	exit 1
fi
trap 'rm -f override.cfg' EXIT
printf '[display]\n\nwindow/size/window_width_override=1080\nwindow/size/window_height_override=1920\n' > override.cfg
capture="$out/still.png"
if command -v cygpath >/dev/null; then capture="$(cygpath -w "$capture")"; fi
"$GODOT" --path . --write-movie "$capture" --fixed-fps 60 res://scenes/record.tscn -- \
	--scenario="$scenario" --stills="$times" "$@"
echo "Stills in $out"
