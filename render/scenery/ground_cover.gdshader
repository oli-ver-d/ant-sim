shader_type canvas_item;
// Ground cover decals (GroundCoverRenderer), one MultiMesh instance each: a
// cell of the baked sprite atlas, tinted, with a soft contact shadow cast away
// from the light (the sprite's own alpha, shifted).
//
// Per-instance data:
//   COLOR       tint (rgb), alpha
//   CUSTOM.x    atlas cell
//   CUSTOM.y    rotation (radians)
//   CUSTOM.z    size of the quad (world units)

uniform sampler2D atlas : filter_linear_mipmap, repeat_disable;
uniform float cells = 4.0;
uniform vec2 light_dir = vec2(-0.55, -0.85);  // direction light comes FROM (world, y down)
uniform float shadow_offset = 0.5;  // world units
uniform float shadow_strength = 0.4;

varying vec4 v_color;
varying vec4 v_custom;

void vertex() {
	v_color = COLOR;
	v_custom = INSTANCE_CUSTOM;
}

vec4 cell_sample(vec2 uv) {
	vec2 c = vec2(mod(v_custom.x, cells), floor(v_custom.x / cells));
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return vec4(0.0);
	}
	return texture(atlas, (c + uv) / cells);
}

void fragment() {
	vec4 t = cell_sample(UV);
	// The shadow falls away from the light: sample the sprite toward the light.
	float a = v_custom.y;
	vec2 L = normalize(light_dir) * shadow_offset / max(v_custom.z, 0.01);
	vec2 local = vec2(cos(a) * L.x + sin(a) * L.y, -sin(a) * L.x + cos(a) * L.y);
	float shadow = cell_sample(UV + local).a * shadow_strength;
	vec3 col = t.rgb * v_color.rgb;
	float alpha = t.a + shadow * (1.0 - t.a);
	COLOR = vec4(col * t.a / max(alpha, 1e-4), alpha * v_color.a);
}
