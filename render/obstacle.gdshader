shader_type canvas_item;
// Draws the obstacle grid smoothly. TEXTURE: R = wall, G = water (one texel
// per cell, linearly filtered); thresholding the interpolated mask gives
// rounded outlines. Walls are rough stone with a shaded rim and a shadow;
// water is dark and deep in the middle with a lighter shallow edge and a
// soft bank.

uniform vec2 world_size = vec2(1080.0, 1920.0);
uniform vec2 light_dir = vec2(-0.55, -0.85);
uniform vec4 stone : source_color = vec4(0.4, 0.35, 0.29, 1.0);
uniform vec4 deep_water : source_color = vec4(0.05, 0.15, 0.22, 1.0);
uniform vec4 shallow_water : source_color = vec4(0.16, 0.34, 0.4, 1.0);

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

void fragment() {
	vec2 w = UV * world_size;
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec2 L = normalize(light_dir);
	vec2 m = texture(TEXTURE, UV).rg;
	// Mask a little way toward the light: tells us which rim faces the light.
	vec2 m_lit = texture(TEXTURE, UV + L * px * 0.8).rg;
	// Shadow: the wall mask shifted away from the light.
	float shadow = texture(TEXTURE, UV + L * px * 1.2).r;

	float aa = max(fwidth(m.r), 0.03);
	float wall = smoothstep(0.5 - aa, 0.5 + aa, m.r);
	float aw = max(fwidth(m.g), 0.03);
	float water = smoothstep(0.5 - aw, 0.5 + aw, m.g);

	vec4 out_col = vec4(0.0);
	// Wall shadow on the ground.
	out_col = vec4(0.0, 0.0, 0.0, smoothstep(0.2, 0.7, shadow) * 0.45 * (1.0 - wall));
	// Damp dark bank around water.
	float bank = smoothstep(0.1, 0.5, m.g) * (1.0 - water);
	out_col = mix(out_col, vec4(0.05, 0.035, 0.02, 0.5), bank);

	if (water > 0.0) {
		float depth = smoothstep(0.5, 1.0, m.g);
		vec3 c = mix(shallow_water.rgb, deep_water.rgb, depth);
		// Soft static ripples / sky reflection.
		float ripple = noise(w / 14.0) * noise(w / 5.0 + 3.0);
		c += vec3(0.08, 0.1, 0.12) * smoothstep(0.35, 0.6, ripple) * depth;
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
