class_name OutputFrame
extends RefCounted
## The output frame: the size in pixels of the rendered video (and of the
## interactive window's content) and the preset of platform UI safe zones
## drawn over it. Render only: the simulation never sees it.
##
## Scenario: "output": {"size": [1920, 1080], "safe_zones": "youtube_shorts"}
## Absent means 1080x1920 portrait with the "tiktok" safe zones, as every
## scenario rendered before the frame size was configurable. A run can
## override the size with --size=WxH (main.tscn, record.tscn, the tools).
##
## Safe zones are margins covered by the app's UI, in pixels of a frame whose
## short side is 1080; they scale with the frame's short side (so a 2160x3840
## frame gets twice the pixels, a 1920x1080 frame the same as 1080x1920).

const DEFAULT_SIZE := Vector2i(1080, 1920)
const DEFAULT_SAFE_ZONES := "tiktok"
## Short side the safe-zone margins and text sizes are given for.
const REFERENCE_SHORT := 1080.0
## Frame presets offered to the user (name -> size).
const PRESETS := {
	"portrait": Vector2i(1080, 1920),
	"landscape": Vector2i(1920, 1080),
	"square": Vector2i(1080, 1080),
	"4:5": Vector2i(1080, 1350),
	"portrait_4k": Vector2i(2160, 3840),
	"landscape_4k": Vector2i(3840, 2160),
}
## Safe-zone margins per preset: top, bottom, left, right (reference pixels).
const SAFE_ZONES := {
	# TikTok / Reels: top bar, caption and buttons at the bottom, action column
	# on the right.
	"tiktok": {"top": 150.0, "bottom": 400.0, "left": 0.0, "right": 120.0},
	# YouTube Shorts: title, channel and progress at the bottom, a wider
	# button column on the right.
	"youtube_shorts": {"top": 120.0, "bottom": 360.0, "left": 0.0, "right": 190.0},
	"none": {"top": 0.0, "bottom": 0.0, "left": 0.0, "right": 0.0},
}
## Smallest and largest width or height accepted.
const MIN_SIDE := 64
const MAX_SIDE := 8192

var size: Vector2i = DEFAULT_SIZE
var safe_zones: String = DEFAULT_SAFE_ZONES

func _init(frame_size: Vector2i = DEFAULT_SIZE, zones: String = DEFAULT_SAFE_ZONES) -> void:
	size = frame_size
	safe_zones = zones if SAFE_ZONES.has(zones) else DEFAULT_SAFE_ZONES

## The frame of a scenario's data ("output" section), with a size override
## ("WxH", e.g. from --size=; "" keeps the scenario's). Bad values fall back
## to the defaults with an error.
static func from_scenario(data: Dictionary, size_override: String = "") -> OutputFrame:
	var out: Dictionary = data.get("output", {})
	var frame := OutputFrame.new(DEFAULT_SIZE, str(out.get("safe_zones", DEFAULT_SAFE_ZONES)))
	if not SAFE_ZONES.has(str(out.get("safe_zones", DEFAULT_SAFE_ZONES))):
		push_error("output.safe_zones: unknown preset '%s' (using %s)" % [out["safe_zones"], DEFAULT_SAFE_ZONES])
	if out.has("size"):
		var s: Variant = out["size"]
		if s is Array and (s as Array).size() == 2:
			frame._set_size(Vector2i(int(s[0]), int(s[1])), "output.size")
		else:
			push_error("output.size must be [width, height] (got %s)" % [s])
	if size_override != "":
		frame._set_size(parse_size(size_override), "--size=" + size_override)
	return frame

## "1920x1080" (or a preset name) -> size; Vector2i.ZERO if it isn't one.
static func parse_size(text: String) -> Vector2i:
	if PRESETS.has(text):
		return PRESETS[text]
	var parts := text.to_lower().split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))

## True if a size can be a frame: both sides even and within MIN_SIDE..MAX_SIDE
## (H.264 in yuv420p needs even sides).
static func valid_size(s: Vector2i) -> bool:
	return s.x >= MIN_SIDE and s.y >= MIN_SIDE and s.x <= MAX_SIDE and s.y <= MAX_SIDE \
			and s.x % 2 == 0 and s.y % 2 == 0

func _set_size(s: Vector2i, source: String) -> void:
	if valid_size(s):
		size = s
	else:
		push_error("%s: not a valid frame size (even sides, %d-%d px); keeping %dx%d" % [source, MIN_SIDE, MAX_SIDE, size.x, size.y])

func size_f() -> Vector2:
	return Vector2(size)

func rect() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(size))

func is_landscape() -> bool:
	return size.x > size.y

func short_side() -> float:
	return float(mini(size.x, size.y))

## Scale of pixel lengths given for a 1080-wide portrait frame (text sizes,
## margins): the frame's short side over 1080.
func scale() -> float:
	return short_side() / REFERENCE_SHORT

## Safe-zone margins in this frame's pixels: {"top", "bottom", "left", "right"}.
func margins() -> Dictionary:
	var m: Dictionary = SAFE_ZONES[safe_zones]
	var s := scale()
	return {"top": m["top"] * s, "bottom": m["bottom"] * s, "left": m["left"] * s, "right": m["right"] * s}

## The part of the frame clear of the platform's UI.
func safe_rect() -> Rect2:
	var m := margins()
	return Rect2(m["left"], m["top"], size.x - m["left"] - m["right"], size.y - m["top"] - m["bottom"])

## The shaded UI areas (top, bottom, left, right; empty ones left out).
func unsafe_rects() -> Array[Rect2]:
	var m := margins()
	var inner := safe_rect()
	var out: Array[Rect2] = []
	for r: Rect2 in [Rect2(0, 0, size.x, m["top"]), Rect2(0, size.y - m["bottom"], size.x, m["bottom"]),
			Rect2(0, inner.position.y, m["left"], inner.size.y),
			Rect2(size.x - m["right"], inner.position.y, m["right"], inner.size.y)]:
		if r.size.x > 0.0 and r.size.y > 0.0:
			out.append(r)
	return out

## Window size for showing this frame on a screen (usable area) of `screen`
## pixels: half the frame (as the 540x960 portrait window), shrunk to fit
## the screen, keeping the aspect.
func window_size(screen: Vector2i) -> Vector2i:
	var f := 0.5
	if screen.x > 0 and screen.y > 0:
		f = minf(f, minf(float(screen.x) / size.x, float(screen.y) / size.y))
	return Vector2i(maxi(roundi(size.x * f), 1), maxi(roundi(size.y * f), 1))

## Makes `window` show this frame: its content is laid out in frame pixels
## (content_scale_size). resize_to_screen also sizes the window to fit the
## screen (interactive runs; recordings get their size from --resolution).
func apply_to_window(window: Window, resize_to_screen: bool) -> void:
	window.content_scale_size = size
	if resize_to_screen and DisplayServer.get_name() != "headless":
		var screen := DisplayServer.screen_get_usable_rect(window.current_screen)
		var want := window_size(screen.size)
		if window.size != want:
			window.size = want
			window.position = screen.position + (screen.size - want) / 2
