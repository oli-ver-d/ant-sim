shader_type canvas_item;
// Draws one ant per MultiMesh instance: three body segments with dome
// lighting and gloss, bilobed head for big-headed castes, mandibles, elbowed
// antennae, six legs in a tripod gait, and a soft drop shadow cast in a fixed
// world-space light direction.
//
// The instance quad is axis-aligned (not rotated); the heading comes in custom
// data so shading and shadow can use world-space directions.
// Per-instance data (packed by AntRenderer):
//   COLOR.rgb       caste colour         COLOR.a       mandible size
//   CUSTOM.x        head scale           CUSTOM.y      abdomen scale
//   CUSTOM.z        floor = thorax scale * 100, fract = leg length / 4
//   CUSTOM.w        floor = heading quantised to 0..1023 + 1024 * fade (0 opaque .. 15),
//                   fract = walk phase / TAU (fade: an ant going through a portal)

// The quad spans QUAD body lengths (legs, antennae and shadow fit inside).
const float QUAD = 2.4;
const float TAU_ = 6.2831853;

uniform vec2 light_dir = vec2(-0.55, -0.85);   // direction light comes FROM (world, y down)
uniform vec2 shadow_offset = vec2(0.09, 0.14); // world offset, in body lengths
uniform float shadow_alpha = 0.5;

varying vec4 v_color;
varying vec4 v_custom;

void vertex() {
	v_color = COLOR;
	v_custom = INSTANCE_CUSTOM;
}

vec2 rot(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

// Approximate signed distance to an axis-aligned ellipse.
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
	float abdomen_s;
	float mandible;
	float leg;
	float phase;
};

vec2 head_centre(Body b) {
	return vec2(0.26 + 0.06 * (b.head_s - 1.0), 0.0);
}

// Distance to the body (abdomen, petiole, thorax, head). `which` returns the
// closest segment: 0 abdomen, 1 thorax, 2 head (for lighting).
float body_sdf(vec2 p, Body b, out int which) {
	float a = sd_ellipse(p, vec2(-0.25, 0.0), vec2(0.22, 0.15) * b.abdomen_s);
	float pet = length(p - vec2(-0.04, 0.0)) - 0.032;
	float t = sd_ellipse(p, vec2(0.07, 0.0), vec2(0.12, 0.062) * b.thorax_s);
	vec2 hc = head_centre(b);
	// Big heads split into two lobes, as in many soldier/major castes.
	float lobe = 0.03 * max(b.head_s - 1.2, 0.0);
	vec2 hr = vec2(0.09, 0.078) * b.head_s;
	float h = min(sd_ellipse(p, hc + vec2(0.0, lobe), hr), sd_ellipse(p, hc - vec2(0.0, lobe), hr));
	which = 0;
	float d = min(a, pet);
	if (t < d) { d = t; which = 1; }
	if (h < d) { d = h; which = 2; }
	return d;
}

// Distance to legs, mandibles and antennae (thin appendages).
float limbs_sdf(vec2 p, Body b) {
	float d = 1e5;
	float w = 0.014;
	// Six legs: attach along the thorax, splay forward / sideways / back.
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		float ax = 0.12 - 0.05 * fk;
		float base = radians(50.0 + 45.0 * fk);
		for (int side = -1; side <= 1; side += 2) {
			float s = float(side);
			// Tripod gait: front+hind of one side move with the middle of the other.
			float group = mod(fk + (s > 0.0 ? 1.0 : 0.0), 2.0);
			float swing = sin(b.phase + group * 3.14159) * 0.32;
			float ang = s * (base - swing);
			vec2 attach = vec2(ax, 0.028 * s * b.thorax_s);
			vec2 knee = attach + vec2(cos(ang), sin(ang)) * 0.2 * b.leg;
			// Tibia bends further back for the hind legs, forward for the front.
			float bend = s * (k == 0 ? -0.5 : (k == 1 ? 0.25 : 0.45));
			vec2 foot = knee + vec2(cos(ang + bend), sin(ang + bend)) * 0.24 * b.leg;
			d = min(d, sd_segment(p, attach, knee) - w);
			d = min(d, sd_segment(p, knee, foot) - w * 0.75);
		}
	}
	vec2 hc = head_centre(b);
	float hs = b.head_s;
	for (int side = -1; side <= 1; side += 2) {
		float s = float(side);
		// Mandibles: short curved jaws at the front of the head.
		vec2 m0 = hc + vec2(0.075, 0.04 * s) * hs;
		vec2 m1 = m0 + vec2(0.06, -0.02 * s) * hs * (0.5 + b.mandible);
		vec2 m2 = m1 + vec2(0.03, -0.03 * s) * hs * (0.5 + b.mandible);
		d = min(d, sd_segment(p, m0, m1) - 0.016 * hs);
		d = min(d, sd_segment(p, m1, m2) - 0.01 * hs);
		// Antennae: scape out to the side, then the flagellum forward, gently swaying.
		vec2 a0 = hc + vec2(0.05, 0.03 * s) * hs;
		vec2 a1 = a0 + vec2(0.05, 0.11 * s);
		vec2 a2 = a1 + vec2(0.15, (0.02 + 0.02 * sin(b.phase * 0.5 + s)) * s);
		d = min(d, sd_segment(p, a0, a1) - 0.009);
		d = min(d, sd_segment(p, a1, a2) - 0.008);
	}
	return d;
}

// Dome normal of the segment closest to p (for lighting).
vec3 dome_normal(vec2 p, Body b, int which) {
	vec2 c;
	vec2 r;
	if (which == 0) {
		c = vec2(-0.25, 0.0);
		r = vec2(0.22, 0.15) * b.abdomen_s;
	} else if (which == 1) {
		c = vec2(0.07, 0.0);
		r = vec2(0.12, 0.062) * b.thorax_s;
	} else {
		c = head_centre(b);
		r = vec2(0.09, 0.078) * b.head_s;
	}
	vec2 q = clamp((p - c) / r, vec2(-1.0), vec2(1.0));
	float z = sqrt(max(1.0 - dot(q, q), 0.05));
	return normalize(vec3(q, z));
}

void fragment() {
	Body b;
	b.head_s = v_custom.x;
	b.abdomen_s = v_custom.y;
	b.thorax_s = floor(v_custom.z) / 100.0;
	b.leg = fract(v_custom.z) * 4.0;
	b.mandible = v_color.a;
	float hw = floor(v_custom.w);
	float fade_steps = floor(hw / 1024.0);
	float heading = (hw - fade_steps * 1024.0) / 1023.0 * TAU_ - 3.14159265;
	// Going down a hole (or coming up): the ant shrinks a little and darkens
	// into the shadow of the funnel first, then fades.
	float gone = fade_steps / 15.0;
	float visible = 1.0 - smoothstep(0.35, 1.0, gone);
	float dim = mix(1.0, 0.3, smoothstep(0.0, 0.6, gone));
	b.phase = fract(v_custom.w) * TAU_;

	// World-oriented quad coordinates (body lengths) -> body space (x forward).
	vec2 q = (UV - 0.5) * QUAD * (1.0 + 0.3 * gone);
	vec2 p = rot(q, -heading);

	int which;
	float bd = body_sdf(p, b, which);
	float ld = limbs_sdf(p, b);
	float aa = fwidth(p.x) * 0.9;
	float body_a = 1.0 - smoothstep(-aa, aa, bd);
	float limb_a = (1.0 - smoothstep(-aa, aa, ld)) * (1.0 - body_a);

	// Lighting in body space.
	vec2 l2 = rot(normalize(light_dir), -heading);
	vec3 L = normalize(vec3(l2, 0.9));
	vec3 n = dome_normal(p, b, which);
	float lambert = max(dot(n, L), 0.0);
	float spec = pow(max(dot(n, normalize(L + vec3(0.0, 0.0, 1.0))), 0.0), 24.0);
	vec3 base = v_color.rgb;
	vec3 body_col = (base * (0.5 + 0.65 * lambert) + vec3(spec * 0.55)) * dim;
	vec3 limb_col = base * 0.75 * dim;

	// Soft drop shadow: the same silhouette offset in world space, blurred.
	vec2 ps = p - rot(shadow_offset, -heading);
	int unused;
	float sd = min(body_sdf(ps, b, unused), limbs_sdf(ps, b) + 0.006);
	float shadow_a = (1.0 - smoothstep(-0.02, 0.07, sd)) * shadow_alpha * (1.0 - gone);

	float ant_a = body_a + limb_a;
	vec3 ant_col = body_col * body_a + limb_col * limb_a;
	float out_a = ant_a + shadow_a * (1.0 - ant_a);
	vec3 out_col = out_a > 0.0 ? ant_col / out_a : vec3(0.0);
	COLOR = vec4(out_col, out_a * visible);
}
