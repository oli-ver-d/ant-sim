shader_type canvas_item;
// Draws a LeafSource. TEXTURE is the leaf's cell mask (R = tissue, G = stem),
// one texel per 3 px cell, linearly filtered: thresholding the interpolated
// mask at 0.5 gives smooth curved outlines and bite arcs at any zoom.
// Colour (veins, mottling) is computed procedurally in leaf-local space and
// must match LeafSource.color_at() on the CPU (used for cut fragments).

uniform vec2 origin;          // local position of the mask's top-left corner
uniform vec2 size;            // mask size in world units
uniform float leaf_length;
uniform float leaf_width;
uniform float cell;
uniform float vein_count;
uniform vec2 vein_dir;        // unit direction of lateral veins (for +y side)
uniform float seed;
uniform vec4 base_color : source_color;
uniform vec4 vein_color : source_color;
uniform vec4 stem_color : source_color;
uniform bool shadow = false;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x),
			mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

// 0..1 vein strength at local position p.
float veins(vec2 p) {
	float t = (p.x + leaf_length * 0.5) / leaf_length;
	float mid_w = cell * (0.35 + 0.45 * (1.0 - t));
	float v = 1.0 - smoothstep(mid_w - 0.5, mid_w + 0.5, abs(p.y));
	vec2 d = vec2(vein_dir.x, vein_dir.y * sign(p.y));
	for (int k = 1; k <= 16; k++) {
		if (float(k) > vein_count) {
			break;
		}
		vec2 rel = p - vec2(-leaf_length * 0.5 + leaf_length * float(k) / (vein_count + 1.0), 0.0);
		float along = dot(rel, d);
		if (along > 0.0) {
			// Lateral veins thin out toward the leaf margin.
			float w = cell * 0.35 * (1.0 - clamp(along / (leaf_width * 0.6), 0.0, 0.7));
			float perp = abs(rel.x * d.y - rel.y * d.x);
			v = max(v, (1.0 - smoothstep(w - 0.5, w + 0.5, perp)) * 0.85);
		}
	}
	return v;
}

void fragment() {
	vec2 m = texture(TEXTURE, UV).rg;
	vec2 p = origin + UV * size;
	float aa_t = max(fwidth(m.r), 0.02);
	float tissue = smoothstep(0.5 - aa_t, 0.5 + aa_t, m.r);
	float aa_s = max(fwidth(m.g), 0.02);
	float stem = smoothstep(0.5 - aa_s, 0.5 + aa_s, m.g) * (1.0 - tissue);

	vec3 c = mix(base_color.rgb, vein_color.rgb, veins(p));
	// Soft mottling at ~7 px scale.
	float n = value_noise(p / 7.0) - 0.5;
	c *= 1.0 + n * 0.12;
	// Darker rim where the mask falls off: the outline and every fresh bite.
	float rim = 1.0 - smoothstep(0.5, 0.9, m.r);
	c *= 1.0 - 0.3 * rim;
	c = mix(c, stem_color.rgb, stem);

	float alpha = max(tissue, stem);
	if (shadow) {
		COLOR = vec4(0.0, 0.0, 0.0, alpha * 0.35);
	} else {
		COLOR = vec4(c, alpha);
	}
}
