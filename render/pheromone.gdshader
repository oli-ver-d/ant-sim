shader_type canvas_item;
render_mode blend_add;
// Soft additive glow for one pheromone channel. TEXTURE holds raw values
// (single float channel); gain converts them to "exposure" units.

uniform vec4 tint : source_color = vec4(1.0);
uniform float gain = 1.0;
uniform float opacity = 0.6;

void fragment() {
	float v = texture(TEXTURE, UV).r * gain;
	// Exponential tone curve: faint trails stay visible, strong ones don't clip.
	float glow = 1.0 - exp(-v);
	COLOR = vec4(tint.rgb, glow * opacity);
}
