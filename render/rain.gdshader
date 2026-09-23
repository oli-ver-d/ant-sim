shader_type canvas_item;
// Rain over one shower's area, seen from above. Drawn twice by RainRenderer:
//   layer 0 (on the ground, under everything else): wet darkening, puddle
//            sheen, and expanding splash rings where drops land;
//   layer 1 (on top of everything): overcast dimming and falling drops,
//            short bright streaks drifting with the wind.
// Drops are procedural: world space is cut into cells and each cell holds one
// drop with a hashed position and phase, so nothing is simulated or stored.
// `clock` is video time (drops look the same speed during a timelapse);
// `intensity` and `wetness` come from sim time (see RainRenderer).

uniform int layer = 0;
uniform vec2 origin;            // world position of this rect's top-left corner
uniform vec2 rect_size;
uniform vec2 world_size = vec2(1080.0, 1920.0);
uniform bool circle = false;    // area shape: circle (centre/radius) or the whole rect
uniform vec2 center;
uniform float radius;
uniform float edge = 60.0;      // soft edge width, world units
uniform float clock = 0.0;
uniform float intensity = 0.0;  // 0-1 how hard it is raining now
uniform float wetness = 0.0;    // 0-1 how wet the ground is (lags the rain, dries slowly)
uniform vec2 wind = vec2(0.35, 1.0);
uniform vec4 wet_color : source_color = vec4(0.03, 0.025, 0.03, 1.0);
uniform vec4 sheen_color : source_color = vec4(0.62, 0.68, 0.78, 1.0);
uniform vec4 drop_color : source_color = vec4(0.82, 0.88, 0.96, 1.0);
uniform vec4 sky_color : source_color = vec4(0.05, 0.07, 0.1, 1.0);

varying vec2 world;

float hash(vec2 p) {
	// Sine-free hash (Dave Hoskins), as in ground.gdshader.
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	world = origin + VERTEX;
}

// 1 inside the shower's area, fading to 0 across the soft edge.
float area_mask(vec2 w) {
	if (circle) {
		return clamp((radius - distance(w, center)) / edge + 0.5, 0.0, 1.0);
	}
	vec2 lo = w - origin;
	vec2 hi = origin + rect_size - w;
	// Sides on the world edge don't fade (the rain continues off-screen).
	if (origin.x <= 0.0) lo.x = 1e6;
	if (origin.y <= 0.0) lo.y = 1e6;
	if (origin.x + rect_size.x >= world_size.x) hi.x = 1e6;
	if (origin.y + rect_size.y >= world_size.y) hi.y = 1e6;
	vec2 d = min(lo, hi);
	return clamp(min(d.x, d.y) / edge + 0.5, 0.0, 1.0);
}

// Splash rings: one drop per `cell` world units, landing once per `period`
// seconds at a hashed spot and time. Returns ring brightness.
float splashes(vec2 w, float cell, float period, float max_r, float salt) {
	float v = 0.0;
	vec2 base = floor(w / cell);
	// Rings can spill into neighbouring cells, so check the 3x3 around.
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = base + vec2(float(x), float(y));
			float h = hash(c + salt);
			// Only some cells get a drop, more of them the harder it rains.
			if (h > intensity * 0.9) continue;
			float t = clock / period + hash(c + salt + 3.7);
			float age = fract(t);
			// A new landing spot every cycle.
			vec2 spot = (c + vec2(hash(c + floor(t) + 1.3), hash(c + floor(t) + 8.1))) * cell;
			float d = distance(w, spot);
			float r = age * max_r;
			float ring = 1.0 - smoothstep(0.0, 0.9, abs(d - r));
			v += ring * (1.0 - age) * (1.0 - age);
			// Bright impact point at the very start.
			v += (1.0 - smoothstep(0.0, 1.6, d)) * max(0.0, 1.0 - age * 6.0) * 1.5;
		}
	}
	return v;
}

// Falling drops: streaks along the wind, in cells that scroll with the wind.
float streaks(vec2 w, float cell, float speed, float len, float salt) {
	vec2 dir = normalize(wind);
	vec2 side = vec2(-dir.y, dir.x);
	// Rain frame: u along the wind, v across it; scroll u with time.
	vec2 q = vec2(dot(w, dir), dot(w, side));
	q.x -= clock * speed;
	vec2 c = floor(q / cell);
	if (hash(c + salt) > intensity * 0.75) return 0.0;
	vec2 f = q - c * cell;
	vec2 spot = vec2(hash(c + salt + 1.1), hash(c + salt + 2.3)) * cell;
	vec2 d = f - spot;
	// Distance to a segment of length `len` along u.
	float along = clamp(d.x, -len * 0.5, len * 0.5);
	float dist = length(vec2(d.x - along, d.y));
	float body = 1.0 - smoothstep(0.25, 0.9, dist);
	// Brighter at the head of the drop.
	return body * (0.35 + 0.65 * (along / len + 0.5)) * (0.5 + 0.5 * hash(c + salt + 4.9));
}

void fragment() {
	vec2 w = world;
	float m = area_mask(w);
	if (layer == 0) {
		// Wet soil: darker all over, darker still with a faint sky reflection
		// where water pools (large smooth patches).
		float pools = smoothstep(0.55, 0.8, noise(w * 0.008 + 5.0) * 0.65 + noise(w * 0.021) * 0.35) * wetness;
		float rings = (splashes(w, 22.0, 0.75, 7.0, 0.0) + splashes(w, 31.0, 0.9, 10.0, 17.0)) * intensity;
		vec3 col = mix(wet_color.rgb, sheen_color.rgb, clamp(pools * 0.12 + rings, 0.0, 1.0));
		float a = wetness * 0.32 + pools * 0.18 + rings * 0.35;
		COLOR = vec4(col, clamp(a, 0.0, 0.8) * m);
	} else {
		float drops = streaks(w, 26.0, 900.0, 11.0, 0.0) * 0.8
				+ streaks(w, 19.0, 1300.0, 16.0, 31.0) * 0.55
				+ streaks(w, 37.0, 650.0, 8.0, 57.0);
		float sky = intensity * 0.22;
		vec3 col = mix(sky_color.rgb, drop_color.rgb, clamp(drops, 0.0, 1.0));
		COLOR = vec4(col, clamp(sky + drops * 0.55 * intensity, 0.0, 0.9) * m);
	}
}
