shader_type canvas_item;
// Draws the obstacle grid smoothly. TEXTURE: R = wall, G = water (one texel
// per cell). The mask is sampled with a bicubic B-spline and nudged by a
// little noise before thresholding, so outlines are rounded and slightly
// irregular instead of following the 4 px cells. Walls are rough stone with a
// shaded rim and a shadow; water is dark and deep in the middle with a
// lighter shallow edge, slowly drifting ripples and a damp bank.

uniform vec2 world_size = vec2(1080.0, 1920.0);
uniform vec2 light_dir = vec2(-0.55, -0.85);
uniform vec4 stone : source_color = vec4(0.4, 0.35, 0.29, 1.0);
uniform vec4 deep_water : source_color = vec4(0.05, 0.15, 0.22, 1.0);
uniform vec4 shallow_water : source_color = vec4(0.16, 0.34, 0.4, 1.0);
// Drift of the ripple pattern on water, world units per second.
uniform vec2 flow = vec2(10.0, 2.0);

float hash(vec2 p) {
	// Sine-free hash (Dave Hoskins): stable across GPUs; sin()-based hashes lose
	// precision for large inputs and show seams between noise cells.
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

vec4 bspline(float v) {
	vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - v;
	vec4 s = n * n * n;
	float x = s.x;
	float y = s.y - 4.0 * s.x;
	float z = s.z - 4.0 * s.y + 6.0 * s.x;
	return vec4(x, y, z, 6.0 - x - y - z) / 6.0;
}

// Bicubic (B-spline) sample using 4 bilinear fetches (TEXTURE can't be used
// in helper functions, so the sampler is passed in).
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
	vec2 w = UV * world_size;
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec2 L = normalize(light_dir);
	// Irregular outlines: shift the lookup by up to ~2 world units of noise.
	vec2 jitter = (vec2(noise(w / 9.0), noise(w / 9.0 + 17.0)) - 0.5) * 4.0 / world_size;
	vec2 uv = UV + jitter;
	vec2 m = texture_bicubic(TEXTURE, uv).rg;
	// Mask a little way toward the light: tells us which rim faces the light.
	vec2 m_lit = texture_bicubic(TEXTURE, uv + L * px * 0.8).rg;
	// Shadow: the wall mask shifted away from the light.
	float shadow = texture_bicubic(TEXTURE, uv + L * px * 1.2).r;

	float aa = max(fwidth(m.r), 0.03);
	float wall = smoothstep(0.5 - aa, 0.5 + aa, m.r);
	float aw = max(fwidth(m.g), 0.03);
	float water = smoothstep(0.5 - aw, 0.5 + aw, m.g);

	vec4 out_col = vec4(0.0);
	// Wall shadow on the ground.
	out_col = vec4(0.0, 0.0, 0.0, smoothstep(0.2, 0.7, shadow) * 0.45 * (1.0 - wall));
	// Damp dark bank around water.
	float bank = smoothstep(0.05, 0.5, m.g) * (1.0 - water);
	out_col = mix(out_col, vec4(0.05, 0.035, 0.02, 0.55), bank);

	if (water > 0.0) {
		float depth = smoothstep(0.5, 1.0, m.g);
		vec3 c = mix(shallow_water.rgb, deep_water.rgb, depth);
		// Ripples: two drifting noise layers; their product gives soft
		// moving highlights (sky reflection) that are brightest mid-stream.
		vec2 drift = flow * TIME;
		float ripple = noise((w - drift) / 16.0) * noise((w - drift * 1.6) / 6.0 + 3.0);
		c += vec3(0.07, 0.09, 0.11) * smoothstep(0.3, 0.6, ripple) * (0.4 + 0.6 * depth);
		// Thin light line where water meets the bank.
		c += vec3(0.06, 0.08, 0.08) * (1.0 - smoothstep(0.5, 0.62, m.g));
		out_col = mix(out_col, vec4(c, 1.0), water);
	}
	if (wall > 0.0) {
		float rough = noise(w / 4.0) * 0.5 + noise(w / 11.0) * 0.5;
		vec3 c = stone.rgb * (0.75 + 0.45 * rough);
		// Rim lighting: edges facing the light are lighter, the others darker.
		float facing = m_lit.r - m.r;
		c *= 1.0 - clamp(facing * 3.0, -0.35, 0.35);
		c *= mix(0.7, 1.0, smoothstep(0.5, 0.85, m.r));
		out_col = mix(out_col, vec4(c, 1.0), wall);
	}
	COLOR = out_col;
}
