shader_type canvas_item;
// The ground under a midden (MiddenRenderer). `data` has one texel per
// Midden stain cell: r = matter rotted into the ground (the stain), g = how
// high the deposits lie there (both 0..1). The stain is a dark, humus-rich
// patch with a soft, wandering edge; the deposits make a mound: its slopes
// are lit and shaded and it casts a soft shadow away from the light, so a big
// pile reads as a heap, not a disc. Fresh refuse sits on top (refuse.gdshader).
// Wet ground under a midden darkens more.

uniform sampler2D data : filter_linear, repeat_disable;
uniform vec2 origin;
uniform float span = 256.0;
uniform float wet = 0.0;
uniform vec3 humus = vec3(0.085, 0.06, 0.04);
uniform vec3 humus_light = vec3(0.2, 0.15, 0.1);
// World units a height of 1 casts its shadow.
uniform float shadow_reach = 7.0;
const vec2 LIGHT_FROM = vec2(-0.55, -0.85);

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

// Both channels smoothed with a 3x3 tent over 1.5-texel steps.
vec2 field(vec2 uv) {
	vec2 px = vec2(1.5) / vec2(textureSize(data, 0));
	vec2 s = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			float w = (x == 0 ? 2.0 : 1.0) * (y == 0 ? 2.0 : 1.0);
			s += texture(data, uv + vec2(float(x), float(y)) * px).rg * w;
		}
	}
	return s / 16.0;
}

// Matter spread wider (a 5x5 tent over 2.5-texel steps): the stain reaches past
// the pile's edge.
float spread(vec2 uv) {
	vec2 px = vec2(2.5) / vec2(textureSize(data, 0));
	float s = 0.0;
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			float w = float(3 - abs(x)) * float(3 - abs(y));
			vec2 t = texture(data, uv + vec2(float(x), float(y)) * px).rg;
			s += (t.r + t.g * 0.8) * w;
		}
	}
	return s / 81.0;
}

void fragment() {
	vec2 world = origin + UV * span;
	vec2 f = field(UV);
	float n = noise(world / 11.0) * 0.6 + noise(world / 3.7) * 0.4;
	// Matter in the ground: the stain, and some under the pile itself.
	float matter = clamp(max(f.r + f.g * 0.8, spread(UV) * 1.6), 0.0, 1.0);
	float cover = smoothstep(0.03, 0.4, matter + (n - 0.5) * 0.3 * (1.0 - matter));
	vec3 col = mix(humus_light, humus, smoothstep(0.1, 0.8, matter)) * (0.85 + 0.3 * noise(world / 2.3));
	float alpha = cover * (0.62 + 0.2 * matter);

	// The mound: slopes shaded from the height's gradient.
	vec2 e = vec2(2.0 / span, 0.0);
	float hx = field(UV + e.xy).g - field(UV - e.xy).g;
	float hy = field(UV + e.yx).g - field(UV - e.yx).g;
	vec3 normal = normalize(vec3(-hx * 6.0, -hy * 6.0, 1.0));
	vec3 L = normalize(vec3(LIGHT_FROM, 0.85));
	float lit = dot(normal, L) / L.z;
	col *= clamp(0.55 + 0.45 * lit, 0.4, 1.5);
	// Cast shadow: higher ground toward the light.
	vec2 toward = normalize(LIGHT_FROM) * shadow_reach / span;
	float over = max(field(UV + toward).g, field(UV + toward * 0.5).g) - f.g;
	float sh = clamp(over * 1.4, 0.0, 0.45);
	col *= 1.0 - 0.3 * wet;
	alpha = min(alpha * (1.0 + 0.3 * wet), 0.95);
	// Shadow (black) under the patch colour.
	float a = alpha + sh * (1.0 - alpha);
	COLOR = vec4(a > 0.0 ? col * alpha / a : col, a);
}
