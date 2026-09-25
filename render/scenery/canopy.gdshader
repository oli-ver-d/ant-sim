shader_type canvas_item;
// Plant canopies (CanopyRenderer): one mesh of every blade, drawn over the
// ants, and the same blades again as their shadow (shadow_pass), shifted away
// from the light on the CPU and drawn first.
//
// Per vertex:
//   UV       x across the blade (-1 and 1 at its edges; the mesh reaches a
//            little past them for anti-aliasing), y along it (0 base, 1 tip)
//   COLOR    tint
//   CUSTOM0  plant centre (xy, world), sway phase, sway per unit distance squared
//   CUSTOM1  style (PlantProp.Style), teeth, blade length (world units),
//            which side faces the light (> 0: the +x half)
// Everything static; only the sway moves, slowly and a little (video bitrate).

uniform bool shadow_pass = false;
uniform vec2 light_dir = vec2(-0.55, -0.85);
uniform sampler2D mottle : filter_linear_mipmap, repeat_enable;
// Wind strength (1 calm; CanopyRenderer raises it in rain) and direction.
uniform float wind = 1.0;
uniform vec2 wind_dir = vec2(0.8, 0.6);
uniform float canopy_alpha = 0.93;
// Opacity left at the tips (fraction of canopy_alpha): the ants show through.
uniform float tip_alpha = 0.5;
uniform float shadow_alpha = 0.27;
// Places the canopy stays thin over: (x, y, radius, unused).
uniform vec4 clear_spots[16];
uniform int clear_count = 0;
uniform float clear_min = 0.18;

const int GRASS = 0;
const int BROAD = 1;
const int LOBE = 2;
const int PINNA = 3;
const int STALK = 4;

varying vec2 world;
varying vec4 v_blade;

void vertex() {
	v_blade = CUSTOM1;
	vec2 r = VERTEX - CUSTOM0.xy;
	float d2 = dot(r, r);
	float d = sqrt(d2);
	float ph = CUSTOM0.z;
	// Slow sway of each blade (its own phase), plus gusts travelling across the ground.
	float s = sin(TIME * 1.1 + ph) * 0.6 + sin(TIME * 0.43 + ph * 1.7) * 0.4;
	float gust = 0.5 + 0.5 * sin(TIME * 0.31 - dot(CUSTOM0.xy, wind_dir) * 0.006);
	vec2 side = d > 0.001 ? vec2(-r.y, r.x) / d : vec2(0.0);
	VERTEX += (side * s * 0.7 + wind_dir * (gust * 0.9 + s * 0.25)) * wind * CUSTOM0.w * d2;
	world = VERTEX;
}

float clear_fade() {
	float f = 1.0;
	for (int i = 0; i < clear_count; i++) {
		vec4 c = clear_spots[i];
		float d = distance(world, c.xy);
		// w = 1: a disc the colony keeps cleared, plants gone right inside.
		bool cleared = c.w > 0.5;
		f *= mix(cleared ? 0.0 : clear_min, 1.0, smoothstep(c.z * (cleared ? 0.8 : 0.55), c.z, d));
	}
	return f;
}

void fragment() {
	int style = int(v_blade.x + 0.5);
	float teeth = v_blade.y;
	float len = v_blade.z;
	float u = UV.x;
	float v = UV.y;
	float au = abs(u);
	float aa = max(fwidth(u), 0.02);

	if (shadow_pass) {
		float a = (1.0 - smoothstep(0.2, 1.0, au / (1.0 + aa * 2.0))) * shadow_alpha;
		COLOR = vec4(0.06, 0.05, 0.02, a * clear_fade());
	} else {
		// Outline: teeth and lobes cut into the edge, a notch at a lobe's tip.
		float edge = 1.0;
		if (style == BROAD && teeth > 0.0) {
			// A few deep lobes pointing back toward the base (dandelion).
			float lobes = clamp(len / 9.0, 3.0, 7.0);
			float saw = 1.0 - fract(v * lobes - au * 0.35);
			edge -= teeth * saw * saw * smoothstep(0.1, 0.25, v) * (1.0 - smoothstep(0.75, 0.9, v));
		} else if (style == PINNA && teeth > 0.0) {
			float lobe = abs(fract(v * len / 2.2) - 0.5) * 2.0;
			edge -= teeth * 0.35 * lobe * lobe;
		}
		float a = 1.0 - smoothstep(edge - aa * 1.5, edge, au);
		if (style == LOBE) {
			float notch = 1.0 - 0.2 * (1.0 - au);
			a *= smoothstep(notch + 0.04, notch - 0.01, v);
		}

		vec3 col = COLOR.rgb;
		float m = texture(mottle, world / 90.0).r;
		col *= 0.88 + 0.24 * m;
		// Folded along the midrib: the half facing the light is brighter.
		float fold = sign(u) * clamp(v_blade.w * 2.0, -1.0, 1.0);
		float fold_k = style == GRASS ? 0.05 : (style == STALK ? 0.0 : 0.13);
		col *= 1.0 + fold_k * fold * smoothstep(0.0, 0.25, au);
		if (style == STALK) {
			// Round: lit along the middle, darker at the sides.
			col *= 0.8 + 0.3 * (1.0 - au * au);
		} else if (style == GRASS) {
			// Fine parallel veins and a paler, drier tip.
			float streak = abs(fract(u * 1.5 + 0.5) - 0.5);
			col *= 0.95 + 0.1 * smoothstep(0.1, 0.25, streak);
			col = mix(col, col * vec3(1.25, 1.15, 0.8), smoothstep(0.75, 1.0, v) * 0.5);
		} else {
			// Midrib, paler than the blade, fading to the tip.
			float mid = 1.0 - smoothstep(0.03, 0.09 + 0.04 * (1.0 - v), au);
			col = mix(col, col * 1.3 + vec3(0.04, 0.05, 0.02), mid * 0.55 * (1.0 - v * 0.6));
			if (style == BROAD) {
				// Side veins sweeping out toward the tip.
				float sv = fract(v * len / 6.0 - au * 0.9);
				float vein = 1.0 - smoothstep(0.0, 0.1, min(sv, 1.0 - sv));
				col = mix(col, col * 1.18, vein * 0.5 * smoothstep(0.1, 0.3, au) * (1.0 - au));
			} else if (style == LOBE && teeth > 0.0) {
				// Pale chevron across the lobe.
				float band = abs(v - (0.42 + 0.3 * au));
				col = mix(col, vec3(0.62, 0.72, 0.55), (1.0 - smoothstep(0.03, 0.08, band)) * 0.45 * (1.0 - au));
			}
		}
		// Light through the thin edges and tips: lighter and yellower there.
		float thin = smoothstep(0.6, 1.0, au) * 0.4 + smoothstep(0.6, 1.0, v) * 0.25;
		col = mix(col, col * vec3(1.25, 1.3, 0.85) + vec3(0.03, 0.04, 0.0), thin);
		// Darker where it joins the ground.
		col *= 0.75 + 0.25 * smoothstep(0.0, 0.2, v);

		a *= canopy_alpha * mix(1.0, tip_alpha, smoothstep(0.3, 1.0, v));
		COLOR = vec4(col, a * clear_fade());
	}
}
