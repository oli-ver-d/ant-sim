# Sourced by the tools: sets FRAME_W, FRAME_H and FRAME_SIZE ("WxH") for a
# scenario's output frame (render/output_frame.gd):
#   SIZE=WxH from the environment if set, else the scenario file's
#   "output": {"size": [w, h]}, else 1080x1920.
#
#   . tools/frame_size.sh; frame_size scenarios/basic_forage.json || exit 1
frame_size() {
	local file="$1" size="${SIZE:-}"
	if [ -z "$size" ] && [ -f "$file" ]; then
		# ScenarioJson writes the output section on one line.
		size="$(grep -m1 '^[[:space:]]*"output":' "$file" \
			| grep -o '"size": *\[ *[0-9]* *, *[0-9]* *\]' \
			| grep -o '[0-9][0-9]*' | paste -sd x - || true)"
	fi
	size="${size:-1080x1920}"
	case "$size" in
		landscape) size=1920x1080 ;;
		portrait) size=1080x1920 ;;
		square) size=1080x1080 ;;
	esac
	if ! [[ "$size" =~ ^([0-9]+)[xX]([0-9]+)$ ]]; then
		echo "Frame size must be WxH, e.g. 1920x1080 (got '$size')" >&2
		return 1
	fi
	FRAME_W="${BASH_REMATCH[1]}"
	FRAME_H="${BASH_REMATCH[2]}"
	if [ $((FRAME_W % 2)) -ne 0 ] || [ $((FRAME_H % 2)) -ne 0 ] || [ "$FRAME_W" -lt 64 ] || [ "$FRAME_H" -lt 64 ] \
			|| [ "$FRAME_W" -gt 8192 ] || [ "$FRAME_H" -gt 8192 ]; then
		echo "Frame size $size: width and height must be even and 64-8192" >&2
		return 1
	fi
	FRAME_SIZE="${FRAME_W}x${FRAME_H}"
}
