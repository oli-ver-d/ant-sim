shader_type canvas_item;
// Side view of an ant for cutaway views, one per MultiMesh instance: gaster,
// two petiole nodes, mesosoma and head as lit domes with a dark rim, mandibles,
// elbowed antennae, and three legs per side (the far side darker, behind the
// body) in a tripod gait. "fold" tucks legs and antennae under the body, as in
// a pupa. Colour comes from the instance, so pale callows and pupae that
// darken as they mature are just colours.
//
// Body space: x forward, y down, in body lengths; the feet stand on y = FOOT.
// The instance transform maps the quad (QUAD body lengths square, centred on
// the body) to the screen, so it can be flipped and tilted along a slope.
// Per-instance data (packed by SideAntRenderer):
//   COLOR.rgb   body colour           COLOR.a     mandible size
//   CUSTOM.x    floor = head scale * 100, fract = thorax scale / 2
//   CUSTOM.y    gaster length scale
//   CUSTOM.z    floor = gaster height scale * 100, fract = fold (0-1)
//   CUSTOM.w    walk phase / TAU (0-1)

const float QUAD = 2.0;
const float FOOT = 0.17;
const float TAU_ = 6.2831853;

uniform vec3 light = vec3(-0.35, -0.8, 0.55);   // direction light comes FROM (y down)
uniform float rim = 0.35;                       // darkening at the outline

varying vec4 v_color;
varying vec4 v_custom;

void vertex() {
	v_color = COLOR;
	v_custom = INSTANCE_CUSTOM;
}

float sd_ellipse(vec2 p, vec2 c, vec2 r) {
	return (length((p - c) / r) - 1.0) * min(r.x, r.y);
}

float sd_segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

struct Body {
	float head_s;
	float thorax_s;
	float gaster_l;
	float gaster_h;
	float fold;
	float mandible;
	float phase;
};

// The gaster hangs from the petiole: a longer or taller one grows backward and up.
vec2 gaster_c(Body b) { return vec2(-0.06 - 0.155 * b.gaster_l, -0.005 - 0.06 * b.gaster_h); }
vec2 gaster_r(Body b) { return vec2(0.16 * b.gaster_l, 0.125 * b.gaster_h); }
vec2 thorax_c(Body b) { return vec2(0.03 + 0.05 * b.thorax_s, -0.05); }
vec2 thorax_r(Body b) { return vec2(0.11, 0.064) * b.thorax_s; }
vec2 head_c(Body b) { return vec2(0.15 + 0.1 * b.thorax_s + 0.06 * (b.head_s - 1.0), -0.06); }
vec2 head_r(Body b) { return vec2(0.088, 0.084) * b.head_s; }

// Body segments; `which` returns the closest: 0 gaster, 1 petiole, 2 thorax, 3 head.
float body_sdf(vec2 p, Body b, out int which) {
	float d = sd_ellipse(p, gaster_c(b), gaster_r(b));
	which = 0;
	float pet = min(length(p - vec2(-0.075, -0.03)) - 0.03, length(p - vec2(-0.025, -0.04)) - 0.028);
	if (pet < d) { d = pet; which = 1; }
	// Mesosoma with a small hump at the front (pronotum).
	float t = min(sd_ellipse(p, thorax_c(b), thorax_r(b)),
			sd_ellipse(p, thorax_c(b) + vec2(0.05, -0.02) * b.thorax_s, vec2(0.05, 0.045) * b.thorax_s));
	if (t < d) { d = t; which = 2; }
	float h = sd_ellipse(p, head_c(b), head_r(b));
	if (h < d) { d = h; which = 3; }
	return d;
}

// One leg: attached at a, knee k, foot f.
float leg_sdf(vec2 p, vec2 a, vec2 k, vec2 f, float w) {
	return min(sd_segment(p, a, k) - w, sd_segment(p, k, f) - w * 0.75);
}

// Legs of one side; side_phase shifts the gait (the far side is half a cycle off).
float legs_sdf(vec2 p, Body b, float side_phase, float w) {
	float d = 1e5;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		vec2 a = vec2(thorax_c(b).x + (0.05 - 0.055 * fi) * b.thorax_s, -0.01);
		// Tripod gait: legs 0 and 2 move together, leg 1 opposite.
		float ph = b.phase + side_phase + (i == 1 ? 3.14159 : 0.0);
		float swing = sin(ph) * 0.07;
		float lift = max(0.0, cos(ph)) * 0.035;
		vec2 foot = vec2(0.36 - 0.3 * fi + swing, FOOT - lift);
		// Femur out and up to a raised knee, tibia splayed down to the ground.
		vec2 knee = vec2(a.x + 0.06 - 0.06 * fi, -0.09);
		// Folded (pupa): legs tucked along the underside.
		vec2 fk = a + vec2(0.07 - 0.02 * fi, 0.035);
		vec2 ff = a + vec2(-0.02 - 0.03 * fi, 0.06);
		d = min(d, leg_sdf(p, a, mix(knee, fk, b.fold), mix(foot, ff, b.fold), w));
	}
	return d;
}

float head_parts_sdf(vec2 p, Body b) {
	vec2 hc = head_c(b);
	float hs = b.head_s;
	// Mandibles: at the front bottom of the head, pointing down and forward.
	vec2 m0 = hc + vec2(0.07, 0.035) * hs;
	vec2 m1 = m0 + vec2(0.05, 0.03) * hs * (0.5 + b.mandible);
	float d = sd_segment(p, m0, m1) - 0.016 * hs;
	// Antennae: scape up and forward, funiculus forward and down (gently
	// waving); folded, they lie down along the face.
	vec2 a0 = hc + vec2(0.04, -0.05) * hs;
	vec2 a1 = a0 + mix(vec2(0.07, -0.1), vec2(0.04, 0.05), b.fold);
	vec2 a2 = a1 + mix(vec2(0.16, 0.05 + 0.03 * sin(b.phase * 0.5)), vec2(-0.06, 0.1), b.fold);
	d = min(d, sd_segment(p, a0, a1) - 0.011);
	d = min(d, sd_segment(p, a1, a2) - 0.009);
	return d;
}

vec3 dome_normal(vec2 p, Body b, int which) {
	vec2 c;
	vec2 r;
	if (which == 0) { c = gaster_c(b); r = gaster_r(b); }
	else if (which == 1) { c = vec2(-0.05, -0.035); r = vec2(0.05, 0.03); }
	else if (which == 2) { c = thorax_c(b); r = thorax_r(b); }
	else { c = head_c(b); r = head_r(b); }
	vec2 q = clamp((p - c) / r, vec2(-1.0), vec2(1.0));
	return normalize(vec3(q, sqrt(max(1.0 - dot(q, q), 0.05))));
}

void fragment() {
	Body b;
	b.head_s = floor(v_custom.x) / 100.0;
	b.thorax_s = fract(v_custom.x) / 0.99 * 2.0;
	b.gaster_l = v_custom.y;
	b.gaster_h = floor(v_custom.z) / 100.0;
	b.fold = fract(v_custom.z) / 0.99;
	b.mandible = v_color.a;
	b.phase = v_custom.w * TAU_;

	vec2 p = (UV - 0.5) * QUAD;
	float aa = fwidth(p.x) * 0.9;
	int which;
	float bd = body_sdf(p, b, which);
	float near_legs = min(legs_sdf(p, b, 0.0, 0.021), head_parts_sdf(p, b));
	float far_legs = legs_sdf(p + vec2(0.02, 0.012), b, 3.14159, 0.018);

	float body_a = 1.0 - smoothstep(-aa, aa, bd);
	float near_a = (1.0 - smoothstep(-aa, aa, near_legs)) * (1.0 - body_a);
	float far_a = (1.0 - smoothstep(-aa, aa, far_legs)) * (1.0 - body_a) * (1.0 - near_a);

	vec3 base = v_color.rgb;
	vec3 n = dome_normal(p, b, which);
	vec3 L = normalize(light);
	float lambert = max(dot(n, L), 0.0);
	float spec = pow(max(dot(n, normalize(L + vec3(0.0, 0.0, 1.0))), 0.0), 20.0);
	vec3 body_col = base * (0.45 + 0.7 * lambert) + vec3(spec * 0.45);
	// Dark rim along the outline so the ant reads against pale backgrounds.
	body_col *= 1.0 - rim * smoothstep(-3.0 * aa, 0.0, bd);
	vec3 near_col = base * 0.7;
	vec3 far_col = base * 0.45;

	float a = body_a + near_a + far_a;
	vec3 col = body_col * body_a + near_col * near_a + far_col * far_a;
	COLOR = vec4(a > 0.0 ? col / a : vec3(0.0), a);
}
