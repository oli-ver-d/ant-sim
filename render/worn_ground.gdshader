shader_type canvas_item;
// Worn ground on the surface (WornGroundRenderer): the traffic map, one texel
// per cell, smoothed over a few cells and multiplied over the ground, so busy
// ground is packed darker and a little cooler in tone without losing its own
// colour. The edge of a path wanders with world-space noise.

render_mode blend_mul;

uniform float traffic_scale = 0.0;
uniform vec3 packed_tint = vec3(0.74, 0.72, 0.72);
uniform float strength = 0.8;

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

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	// A 3x3 tent over 1.5-cell steps: cells blur into smooth paths.
	float t = 0.0;
	float wsum = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			float w = (2.0 - abs(float(x))) * (2.0 - abs(float(y)));
			t += texture(TEXTURE, UV + vec2(float(x), float(y)) * px * 1.5).r * w;
			wsum += w;
		}
	}
	t /= wsum;
	float wear = 1.0 - exp(-max(t, 0.0) * traffic_scale);
	// Ragged edges: a little noise in cells (UV / px = cell coordinates).
	vec2 cell = UV / px;
	wear = smoothstep(0.08, 0.9, wear + (noise(cell * 0.6) - 0.5) * 0.18);
	COLOR = vec4(mix(vec3(1.0), packed_tint, wear * strength), 1.0);
}
