class_name Presentation
extends CanvasLayer
## Cinematic presentation over the whole 1080x1920 frame (over the split
## layout too), driven by video time. All render only. From the scenario's
## "render" section:
##
##   "captions": [{"t": 2, "until": 8, "text": "A queen lands", "style": "title",
##                 "pos": "middle", "fade": 0.8}, ...]
##       style "title" (large), "chapter" (medium, small caps look) or "caption"
##       (default); pos "top", "middle" or "bottom" (default), each inside the
##       TikTok/Reels safe area (Overlays.SafeZones); "\n" breaks lines, long
##       lines wrap. Faded in after t and out before until over `fade` seconds.
##   "fades": [{"t": 58, "to": 0}, {"t": 60, "to": 1}, {"t": 61, "to": 0}]
##       a full-frame colour ("color": [r, g, b], default black) whose opacity
##       ramps between the points (1 = the frame is that colour).
##   "grade": [{"t": 0, "tint": [1, 0.9, 0.8], "brightness": 1, "contrast": 1,
##              "saturation": 1, "vignette": 0.3}, ...]
##       a colour grade (dawn, noon, dusk, night) ramped between points.
##
## Points of fades and grade are sorted by t; a key missing from a point keeps
## the previous point's value. Between two points values follow the second
## point's "ease" ("linear", "in", "out", "in_out"; default "in_out").

const FRAME := Vector2(1080, 1920)
## Horizontal margin of captions (clear of the right-hand UI column).
const CAPTION_MARGIN := 130.0
const STYLES := {
	"title": {"size": 84, "outline": 14, "color": Color(1.0, 0.97, 0.9)},
	"chapter": {"size": 58, "outline": 11, "color": Color(1.0, 0.9, 0.7)},
	"caption": {"size": 44, "outline": 9, "color": Color(1.0, 0.98, 0.94)},
}
const GRADE_DEFAULTS := {"tint": [1.0, 1.0, 1.0], "brightness": 1.0, "contrast": 1.0,
		"saturation": 1.0, "vignette": 0.0}
const FADE_DEFAULTS := {"to": 0.0, "color": [0.0, 0.0, 0.0]}

var captions: Array[Dictionary] = []
var fades: Array[Dictionary] = []
var grade: Array[Dictionary] = []
## Shows or hides the captions (--captions=0 records a text-free cut).
var captions_visible := true
var video_time := 0.0

var _grade_rect: ColorRect
var _fade_rect: ColorRect
var _caption_layer: Control

## True if the scenario's render section asks for any presentation.
static func wanted(render: Dictionary) -> bool:
	return render.has("captions") or render.has("fades") or render.has("grade")

func setup(render: Dictionary) -> void:
	layer = 5
	for c: Dictionary in render.get("captions", []):
		captions.append(c)
	fades = _points(render.get("fades", []), FADE_DEFAULTS)
	grade = _points(render.get("grade", []), GRADE_DEFAULTS)
	if not grade.is_empty():
		_grade_rect = ColorRect.new()
		_grade_rect.size = FRAME
		_grade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://render/grade.gdshader")
		_grade_rect.material = mat
		add_child(_grade_rect)
	if not fades.is_empty():
		_fade_rect = ColorRect.new()
		_fade_rect.size = FRAME
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_fade_rect)
	_caption_layer = Control.new()
	_caption_layer.size = FRAME
	_caption_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption_layer.draw.connect(_draw_captions)
	add_child(_caption_layer)
	update(0.0)

## Called every frame with the video time.
func update(t: float) -> void:
	video_time = t
	if _grade_rect != null:
		var g := grade_at(t)
		var mat := _grade_rect.material as ShaderMaterial
		mat.set_shader_parameter("tint", _color(g["tint"]))
		mat.set_shader_parameter("brightness", float(g["brightness"]))
		mat.set_shader_parameter("contrast", float(g["contrast"]))
		mat.set_shader_parameter("saturation", float(g["saturation"]))
		mat.set_shader_parameter("vignette", float(g["vignette"]))
	if _fade_rect != null:
		var f := fade_at(t)
		var c := _color(f["color"])
		c.a = clampf(float(f["to"]), 0.0, 1.0)
		_fade_rect.color = c
		_fade_rect.visible = c.a > 0.0
	_caption_layer.visible = captions_visible
	_caption_layer.queue_redraw()

## The fade point values ("to", "color") at video time t.
func fade_at(t: float) -> Dictionary:
	return ramp(fades, t) if not fades.is_empty() else FADE_DEFAULTS.duplicate()

## The grade values at video time t.
func grade_at(t: float) -> Dictionary:
	return ramp(grade, t) if not grade.is_empty() else GRADE_DEFAULTS.duplicate()

## Opacity (0-1) of a caption at video time t.
static func caption_alpha(c: Dictionary, t: float) -> float:
	var start := float(c.get("t", 0.0))
	var end := float(c.get("until", start + 4.0))
	if t < start or t > end:
		return 0.0
	var fade := maxf(float(c.get("fade", 0.8)), 0.001)
	return clampf(minf((t - start) / fade, (end - t) / fade), 0.0, 1.0)

## Points sorted by t, each with every key (missing keys carried over from the
## previous point, or `defaults` for the first).
static func _points(list: Array, defaults: Dictionary) -> Array[Dictionary]:
	var sorted: Array[Dictionary] = []
	for p: Dictionary in list:
		sorted.append(p)
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
	var out: Array[Dictionary] = []
	var last := defaults.duplicate()
	for p in sorted:
		var full := last.duplicate()
		full.merge(p, true)
		out.append(full)
		last = full
	return out

## Values of full points (see _points) at time t: numbers and number arrays
## are interpolated with the later point's easing.
static func ramp(points: Array[Dictionary], t: float) -> Dictionary:
	var n := points.size()
	if t <= float(points[0]["t"]):
		return points[0].duplicate()
	if t >= float(points[n - 1]["t"]):
		return points[n - 1].duplicate()
	var k := 0
	while float(points[k + 1]["t"]) < t:
		k += 1
	var a := points[k]
	var b := points[k + 1]
	var u := (t - float(a["t"])) / maxf(float(b["t"]) - float(a["t"]), 0.0001)
	var e := CameraDirector._ease(u, str(b.get("ease", "in_out")))
	var out := {}
	for key: String in b:
		var va: Variant = a.get(key, b[key])
		var vb: Variant = b[key]
		if (va is float or va is int) and (vb is float or vb is int):
			out[key] = lerpf(float(va), float(vb), e)
		elif va is Array and vb is Array and (va as Array).size() == (vb as Array).size():
			var aa: Array = va
			var ab: Array = vb
			var arr := []
			for i in aa.size():
				arr.append(lerpf(float(aa[i]), float(ab[i]), e))
			out[key] = arr
		else:
			out[key] = vb
	return out

static func _color(v: Variant) -> Color:
	var a: Array = v
	return Color(float(a[0]), float(a[1]), float(a[2]))

func _draw_captions() -> void:
	var font := ThemeDB.fallback_font
	var width := FRAME.x - 2.0 * CAPTION_MARGIN
	for c in captions:
		var alpha := caption_alpha(c, video_time)
		if alpha <= 0.0:
			continue
		var style: Dictionary = STYLES.get(str(c.get("style", "caption")), STYLES["caption"])
		var fs: int = style["size"]
		var text := str(c.get("text", ""))
		var box := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, width, fs)
		var y := 0.0
		match str(c.get("pos", "bottom")):
			"top":
				y = Overlays.SafeZones.TOP + 60.0
			"middle":
				y = (FRAME.y - box.y) * 0.5
			_:
				y = FRAME.y - Overlays.SafeZones.BOTTOM - 50.0 - box.y
		var at := Vector2(CAPTION_MARGIN, y + font.get_ascent(fs))
		# Rise a little while fading in.
		at.y += (1.0 - alpha) * 12.0
		var col: Color = style["color"]
		col.a = alpha
		var shadow := Color(0.02, 0.015, 0.01, 0.55 * alpha)
		_caption_layer.draw_multiline_string_outline(font, at + Vector2(0, 4), text,
				HORIZONTAL_ALIGNMENT_CENTER, width, fs, -1, int(style["outline"]) + 6, shadow)
		_caption_layer.draw_multiline_string_outline(font, at, text,
				HORIZONTAL_ALIGNMENT_CENTER, width, fs, -1, int(style["outline"]), Color(0.03, 0.02, 0.01, 0.85 * alpha))
		_caption_layer.draw_multiline_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, fs, -1, col)
