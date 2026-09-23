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
	// Sine-free hash (Dave Hoskins): stable across GPUs; sin()-based hashes lose
	// precision for large inputs and show seams between noise cells.
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
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

// Cubic B-spline weights for fractional position v.
vec4 bspline(float v) {
	vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - v;
	vec4 s = n * n * n;
	float x = s.x;
	float y = s.y - 4.0 * s.x;
	float z = s.z - 4.0 * s.y + 6.0 * s.x;
	return vec4(x, y, z, 6.0 - x - y - z) / 6.0;
}

// Bicubic (B-spline) sample using 4 bilinear fetches. Thresholding a bilinear
// mask leaves visible corners at cell scale when zoomed in; the B-spline gives
// smooth, rounded outlines and bite arcs.
vec4 texture_bicubic(sampler2D tex, vec2 uv) {
	vec2 tex_size = vec2(textureSize(tex, 0));
	vec2 inv = 1.0 / tex_size;
	uv = uv * tex_size - 0.5;
	vec2 f = fract(uv);
	uv -= f;
	vec4 xc = bspline(f.x);
	vec4 yc = bspline(f.y);
	vec4 c = uv.xxyy + vec2(-0.5, 1.5).xyxy;
	vec4 s = vec4(xc.xz + xc.yw, yc.xz + yc.yw);
	vec4 o = (c + vec4(xc.yw, yc.yw) / s) * inv.xxyy;
	vec4 s0 = texture(tex, o.xz);
	vec4 s1 = texture(tex, o.yz);
	vec4 s2 = texture(tex, o.xw);
	vec4 s3 = texture(tex, o.yw);
	float sx = s.x / (s.x + s.y);
	float sy = s.z / (s.z + s.w);
	return mix(mix(s3, s2, sx), mix(s1, s0, sx), sy);
}

void fragment() {
	vec2 m = texture_bicubic(TEXTURE, UV).rg;
	vec2 p = origin + UV * size;
	float aa_t = max(fwidth(m.r), 0.02);
	float tissue = smoothstep(0.5 - aa_t, 0.5 + aa_t, m.r);
	float aa_s = max(fwidth(m.g), 0.02);
	float stem = smoothstep(0.5 - aa_s, 0.5 + aa_s, m.g) * (1.0 - tissue);

	vec3 c = mix(base_color.rgb, vein_color.rgb, veins(p));
	// Soft mottling at ~7 px scale.
	float n = value_noise(p / 7.0 + seed) - 0.5;
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
