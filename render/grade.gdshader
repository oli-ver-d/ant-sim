shader_type canvas_item;
// Full-frame colour grade (Presentation): reads what is already drawn and
// applies tint, brightness, contrast, saturation and a vignette.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec3 tint = vec3(1.0);
uniform float brightness = 1.0;
uniform float contrast = 1.0;
uniform float saturation = 1.0;
uniform float vignette = 0.0;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(luma), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	c *= tint * brightness;
	// Vignette on the portrait frame: an ellipse, darker toward the corners.
	vec2 d = (UV - 0.5) * vec2(1.0, 1.35);
	float v = smoothstep(0.35, 0.95, length(d) * 1.25);
	c *= 1.0 - vignette * v;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
