shader_type canvas_item;
// One nest entrance on the surface (EntranceRenderer), on a square quad
// centred on the opening. Everything comes from a height field H(p) (world
// units, p relative to the opening): the hole drops away inside a noise-
// warped rim, and each style adds its own relief round it:
//   0 hole    a raised lip of packed soil and a worn apron
//   1 crater  a funnel rising to a ring of grit and fine pebbles, heavier on
//             the side the spoil goes
//   2 mound   a low cone of loose soil with the hole on top, cut by radial
//             erosion runnels
//   3 turret  a small raised collar with its own shadow
// Lighting: the normal from H, lit from light_dir (like the ants and props),
// a cast shadow marched toward the light, and depth darkening that takes the
// throat of the hole to black. So the inner wall is lit on the side away from
// the light and in deep shadow on the near side. A sealed entrance is a soil
// plug with scuffed crumbs instead of a hole.
// All noise is a function of world position (static; compresses well).

uniform vec2 center;              // world position of the opening
uniform float hole = 10.0;        // opening radius (world units)
uniform float reach = 30.0;       // half the quad's size; everything fades out by here
uniform int style = 0;
uniform float open = 1.0;         // 1 open, 0 sealed
uniform float wear = 0.0;         // 0..1: how much it has been used (packed, darker rim)
uniform vec2 spoil_dir = vec2(0.0);  // toward the spoil heap (unit), or zero
uniform float seed = 0.0;
uniform vec2 light_dir = vec2(-0.55, -0.85);  // direction light comes FROM (world, y down)

// What's drawn under the entrance (ground, worn ground, cleared disc): the
// entrance only reshapes and shades it, so it sits on any ground material.
uniform sampler2D screen : hint_screen_texture, filter_linear;

// Lighting of flat ground: 0.3 + 0.95 * L.z for the light below.
const float FLAT = 0.9308;

const int HOLE = 0;
const int CRATER = 1;
const int MOUND = 2;
const int TURRET = 3;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Height of round bumps on a jittered grid (grit, crumbs, pebbles): 0..1.
float bumps(vec2 p, float density) {
	vec2 i = floor(p);
	float h = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = i + vec2(float(x), float(y));
			if (hash(c + 19.1) > density) {
				continue;
			}
			vec2 o = vec2(hash(c), hash(c + 5.3));
			float r = 0.25 + 0.3 * hash(c + 11.7);
			float d = length(p - c - o) / r;
			h = max(h, sqrt(max(1.0 - d * d, 0.0)) * (0.6 + 0.4 * hash(c + 2.9)));
		}
	}
	return h;
}

// Rim radius in the direction of p: the opening is not a circle.
float rim_radius(vec2 p) {
	vec2 d = p / max(length(p), 1e-3);
	vec2 w = center + seed * 17.0;
	return hole * (0.88 + 0.26 * noise(d * 2.2 + w * 0.01) + 0.08 * noise(d * 6.0 - w * 0.01));
}

float height(vec2 p) {
	float q = length(p);
	float s = q / rim_radius(p);
	vec2 w = center + p;
	vec2 dir = p / max(q, 1e-3);
	float h = 0.0;
	if (style == HOLE) {
		// Lip of packed soil just outside the rim, a ring of fine crumbs on it.
		float lip = exp(-pow((s - 1.25) / 0.3, 2.0));
		h = hole * 0.28 * lip + bumps(w * 1.3, 0.55) * 0.35 * lip;
	} else if (style == CRATER) {
		// Funnel up to a crest, then down to the ground; the crest sits further
		// out and higher on the spoil side and is uneven all round.
		float side = max(dot(dir, spoil_dir), 0.0);
		float crest = 2.1 + 0.5 * side + 0.35 * (noise(dir * 1.8 + center * 0.01) - 0.5);
		float top = hole * (0.32 + 0.18 * side);
		float up = smoothstep(1.0, crest, s);
		float down = 1.0 - smoothstep(crest, crest + 1.0 + 0.3 * side, s);
		h = top * up * up * (3.0 - 2.0 * up) * down;
		// Grit and small pebbles on the ring (fewer down the funnel).
		float g = bumps(w * 1.4, 0.7) * 0.25 + bumps(w * 0.55 + 3.1, 0.35) * 0.6;
		h += g * smoothstep(1.1, 1.8, s) * down;
	} else if (style == MOUND) {
		// A cone: steep near the top, spreading low toward its foot.
		// Lobed foot: soil slumps further out in places.
		float foot = reach / hole * (0.66 + 0.26 * noise(dir * 1.6 + center * 0.013));
		float t = clamp((s - 1.0) / (foot - 1.0), 0.0, 1.0);
		float cone = pow(1.0 - t, 1.5);
		// Radial runnels: grooves along the slope, wandering a little.
		float n = noise(dir * 3.6 + vec2(s * 0.18) + center * 0.02);
		float groove = 1.0 - abs(2.0 * n - 1.0);
		h = hole * 1.8 * cone * (1.0 - 0.28 * groove * smoothstep(1.2, 2.2, s));
		// Loose crumbs all over, and a rounded top edge round the hole.
		h += bumps(w * 0.9, 0.6) * 0.45 * smoothstep(1.0, 1.4, s) * (0.4 + 0.6 * cone);
		h -= hole * 0.2 * (1.0 - smoothstep(1.0, 1.5, s));
	} else {
		// A collar with steep sides and a rounded top.
		float wall = smoothstep(0.92, 1.08, s) * (1.0 - smoothstep(1.4, 1.75, s));
		h = hole * 0.75 * wall * (0.9 + 0.2 * noise(w * 0.5));
		h += bumps(w * 1.1, 0.5) * 0.3 * wall;
	}
	// The hole: a steep wall down to a throat too deep to see into.
	float inside = 1.0 - smoothstep(0.5, 1.0, s);
	float drop = hole * 2.2 * inside;
	// Sealed: a plug of loose soil, slightly sunk, with scuffed crumbs.
	float plug = inside * (-hole * 0.12 + bumps(w * 1.2, 0.6) * 0.4 + noise(w * 0.7) * 0.3);
	return h - drop * open + plug * (1.0 - open);
}

// The colour before lighting, from the ground already drawn under it.
vec3 soil_color(vec3 ground, vec2 p, float h, float s) {
	vec2 w = center + p;
	vec3 col = ground;
	// Fresh dug-out soil: lighter and redder than most ground, some of the
	// ground's own colour kept.
	vec3 loose = mix(ground * vec3(1.2, 1.1, 1.0), vec3(0.45, 0.33, 0.22), 0.5) * (0.9 + 0.2 * noise(w * 0.8));
	if (style == HOLE) {
		col = mix(col, loose, 0.7 * exp(-pow((s - 1.3) / 0.35, 2.0)));
	} else if (style == CRATER) {
		// Pale grit, lighter up on the ring, pebbles each their own shade.
		vec3 grit = mix(vec3(0.5, 0.42, 0.3), vec3(0.6, 0.52, 0.38), noise(w * 0.9));
		grit *= 0.85 + 0.3 * hash(floor(w * 0.55 + 3.1));
		col = mix(col, grit, smoothstep(1.0, 1.9, s) * clamp(h / (hole * 0.3) + 0.3, 0.0, 1.0));
	} else if (style == MOUND) {
		// Fresh loose soil, a little lighter and redder than the ground,
		// freshest toward the top; it thins out toward the foot.
		float fresh = clamp(h / (hole * 0.8), 0.0, 1.0);
		col = mix(col, loose, smoothstep(0.0, 0.25, fresh) * (0.6 + 0.4 * fresh));
	} else if (style == TURRET) {
		col = mix(col, loose, smoothstep(0.9, 1.1, s) * (1.0 - smoothstep(1.6, 2.0, s)));
	}
	// Packed, darker soil where the traffic goes in and out.
	float packed = (1.0 - smoothstep(1.0, 2.0, s)) * (0.2 + 0.4 * wear);
	col *= 1.0 - 0.3 * packed;
	// Sealed plug: crumbly, a little darker than what's round it.
	if (open < 0.5) {
		col = mix(col, ground * 0.8 * (0.85 + 0.3 * noise(w * 1.3)), 1.0 - smoothstep(0.7, 1.05, s));
	}
	return col;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * reach;
	float q = length(p);
	float rr = rim_radius(p);
	float s = q / rr;
	float e = max(0.25, reach / 160.0);
	float h = height(p);
	vec2 g = vec2(height(p + vec2(e, 0.0)) - height(p - vec2(e, 0.0)),
			height(p + vec2(0.0, e)) - height(p - vec2(0.0, e))) / (2.0 * e);
	vec3 n = normalize(vec3(-g, 1.0));
	vec2 l2 = normalize(light_dir);
	vec3 L = normalize(vec3(l2, 0.9));
	float lambert = max(dot(n, L), 0.0);
	// Cast shadow: march toward the light; anything above the light ray shades.
	float rise = L.z / length(L.xy);
	float shade = 0.0;
	float step_len = hole * 0.22;
	for (int k = 1; k <= 8; k++) {
		float t = float(k) * step_len;
		float over = height(p + l2 * t) - (h + t * rise);
		shade = max(shade, clamp(over / (hole * 0.25), 0.0, 1.0));
	}
	vec3 ground = texture(screen, SCREEN_UV).rgb;
	vec3 col = soil_color(ground, p, h, s);
	// Relative to flat ground (lit at FLAT), which keeps its own colour.
	float light = (0.3 + 0.95 * lambert) / FLAT * (1.0 - 0.6 * shade);
	col *= light;
	// Depth: the throat goes to black, the lit wall keeps a little warmth.
	float depth = clamp(-h / (hole * 2.0), 0.0, 1.0);
	col *= mix(1.0, 0.02, pow(depth, 0.7));
	// Fade into the ground toward the edge of the drawing, raggedly.
	float edge = reach * (0.8 + 0.2 * noise((center + p) * 0.08));
	COLOR = vec4(col, 1.0 - smoothstep(edge * 0.7, edge, q));
}
