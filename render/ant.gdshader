shader_type canvas_item;
// Draws one ant per MultiMesh instance on a unit quad. The ant faces +x.
// Per-instance data (set by AntRenderer):
//   COLOR           caste colour
//   INSTANCE_CUSTOM (head_scale, thorax_scale, abdomen_scale, walk phase)
// The quad spans QUAD_SCALE body lengths so legs/shadow (added later) fit.

const float QUAD_SCALE = 1.6;

varying vec4 v_custom;
varying vec4 v_color;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_color = COLOR;
}

// Antialiased filled ellipse: 1 inside, 0 outside.
float ellipse(vec2 p, vec2 center, vec2 radius) {
	float d = length((p - center) / radius) - 1.0;
	float aa = fwidth(d);
	return 1.0 - smoothstep(-aa, aa, d);
}

void fragment() {
	// Body space: x forward in [-0.5, 0.5] = one body length.
	vec2 p = (UV - 0.5) * QUAD_SCALE;
	float head_s = v_custom.x;
	float thorax_s = v_custom.y;
	float abdomen_s = v_custom.z;

	float abdomen = ellipse(p, vec2(-0.24, 0.0), vec2(0.21, 0.14) * abdomen_s);
	float thorax = ellipse(p, vec2(0.04, 0.0), vec2(0.12, 0.065) * thorax_s);
	float head = ellipse(p, vec2(0.24 + 0.04 * (head_s - 1.0), 0.0), vec2(0.1, 0.1) * head_s);

	float alpha = max(abdomen, max(thorax, head));
	// Slightly darker head and abdomen tip for definition.
	float shade = mix(1.0, 0.8, head) * mix(1.0, 0.85, abdomen * smoothstep(-0.2, -0.4, p.x));
	COLOR = vec4(v_color.rgb * shade, v_color.a * alpha);
}
