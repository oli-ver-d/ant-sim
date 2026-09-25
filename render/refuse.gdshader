shader_type canvas_item;
// Deposits on a midden (MiddenRenderer), drawn from a RefuseLook atlas. Each
// draw's colour carries the deposit, not a plain modulate: rgb is its tint
// (a dead worker's caste colour, white otherwise) and alpha how far it has
// rotted (0 fresh .. 1 gone). Rotting refuse loses its colour, darkens toward
// humus and flattens: less contrast, a shorter shadow. The shadow is cast
// from the sprite's own outline, away from the light. Wet refuse is darker
// and glossy on its lit tops.

uniform float wet = 0.0;
// Sprite pixels the shadow falls from the body of a fresh deposit.
uniform float shadow_px = 2.2;
uniform vec3 humus = vec3(0.13, 0.095, 0.065);
// Direction the light comes from (world, y down), as PropBaker.LIGHT_DIR.
const vec2 LIGHT_FROM = vec2(-0.55, -0.85);

// The draw colour as given (in fragment(), COLOR has the texture in it).
varying vec4 deposit;

void vertex() {
	deposit = COLOR;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float rot = deposit.a;
	vec3 col = tex.rgb * deposit.rgb;
	float grey = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(grey), rot * 0.6);
	// Rotting down into humus: darker, and flatter (the shading fades into
	// the humus colour too).
	col = mix(col, humus * (0.8 + 0.4 * grey), smoothstep(0.0, 1.0, rot) * 0.8);
	float lum = dot(tex.rgb, vec3(0.3, 0.59, 0.11));
	col *= 1.0 - 0.38 * wet;
	col += vec3(0.9, 0.92, 0.95) * wet * 0.32 * smoothstep(0.62, 0.95, lum) * (1.0 - rot * 0.7);
	vec2 off = -normalize(LIGHT_FROM) * shadow_px * (1.0 - 0.6 * rot) * TEXTURE_PIXEL_SIZE;
	float sh = texture(TEXTURE, UV - off).a * (0.34 - 0.14 * rot);
	float a = tex.a + sh * (1.0 - tex.a);
	COLOR = vec4(a > 0.0 ? col * tex.a / a : col, a);
}
