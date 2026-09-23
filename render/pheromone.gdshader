shader_type canvas_item;
render_mode blend_add;
// Soft additive glow for one pheromone channel. TEXTURE holds raw values
// (single float channel, one texel per grid cell); gain converts them to
// "exposure" units. A tight core plus a wide soft halo reads as light rather
// than a heatmap, and busy trails get a slightly whiter hot centre.

uniform vec4 tint : source_color = vec4(1.0);
uniform float gain = 1.0;
// Raw values below this (in exposure units) are not drawn: hides faint haze.
uniform float cutoff = 0.04;
uniform float opacity = 0.6;
uniform float halo_radius = 2.5;   // in cells
uniform float halo_strength = 0.7;

float sample_v(sampler2D tex, vec2 uv) {
	return texture(tex, uv).r;
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	float core = sample_v(TEXTURE, UV);
	// Halo: two rings of 8 taps.
	float halo = 0.0;
	for (int k = 0; k < 8; k++) {
		float a = float(k) * 0.785398 + 0.39;
		vec2 dir = vec2(cos(a), sin(a));
		halo += sample_v(TEXTURE, UV + dir * px * halo_radius * 0.5);
		halo += sample_v(TEXTURE, UV + dir * px * halo_radius);
	}
	halo /= 16.0;
	float v = max((core * 0.55 + halo * halo_strength) * gain - cutoff, 0.0);
	// Exponential tone curve: faint trails stay visible, strong ones don't clip.
	float glow = 1.0 - exp(-v);
	vec3 col = mix(tint.rgb, vec3(1.0), smoothstep(0.8, 1.0, glow) * 0.18);
	COLOR = vec4(col, glow * opacity);
}
