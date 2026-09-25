shader_type canvas_item;
// Brood seen from above, one MultiMesh instance each:
//   egg     a glossy cream ellipse, slightly translucent
//   larva   a curled C-shaped grub, segmented, with a small amber head capsule;
//           plumper as it grows, duller when hungry
//   pupa    a folded worker: head, thorax and gaster in a pale casing with the
//           legs and antennae pressed along the body; eyes darken first, then
//           the whole body tans as it matures
//   callow  the casing split, a pale amber young worker inside
// Dirt shows as a grey-green fuzz of speckles.
//
// Per-instance data (packed by BroodRenderer):
//   COLOR.rgb   tint (pupa/callow body colour of its caste), COLOR.a  alpha
//   CUSTOM.x    stage (0 egg, 1 larva, 2 pupa, 3 callow)
//   CUSTOM.y    progress through the stage (0-1), or larva growth
//   CUSTOM.z    dirt (0-1) + 2 * floor(hunger * 100) (hunger 0-1, larvae)
//   CUSTOM.w    heading (radians) + 100 * look seed (0-99)

uniform vec2 light_dir = vec2(-0.55, -0.85);

varying vec4 v_color;
varying vec4 v_custom;

void vertex() {
	v_color = COLOR;
	v_custom = INSTANCE_CUSTOM;
}

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 rot(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

float sd_ellipse(vec2 p, vec2 c, vec2 r) {
	return (length((p - c) / r) - 1.0) * min(r.x, r.y);
}

float sd_segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

// Dome lighting for a blob whose "height" falls off with the signed distance d
// (negative inside), `r` its half thickness.
vec3 dome(vec2 grad, float d, float r) {
	float h = clamp(-d / r, 0.0, 1.0);
	return normalize(vec3(grad * (1.0 - h) * 1.4, 0.35 + h));
}

void fragment() {
	int stage = int(v_custom.x + 0.5);
	float t = v_custom.y;
	float dirt = min(v_custom.z - 2.0 * floor(v_custom.z * 0.5), 1.0);
	float hunger = floor(v_custom.z * 0.5) / 100.0;
	float heading = v_custom.w - 100.0 * floor(v_custom.w / 100.0 + 0.5);
	float look = floor(v_custom.w / 100.0 + 0.5);
	vec2 p = rot((UV - 0.5) * 2.0, -heading);
	vec2 Lw = rot(normalize(light_dir), -heading);
	vec3 L = normalize(vec3(-Lw, 0.9));
	float aa = fwidth(p.x) * 1.2;

	float d = 1e5;
	vec3 base = vec3(0.97, 0.95, 0.86);
	float gloss = 0.6;
	float half_thick = 0.4;
	vec2 g = vec2(0.0);
	float detail = 0.0;

	if (stage == 0) {
		// Egg.
		d = sd_ellipse(p, vec2(0.0), vec2(0.62, 0.44));
		g = p / vec2(0.62, 0.44);
		half_thick = 0.44;
		base = vec3(0.98, 0.96, 0.87);
		gloss = 1.0;
	} else if (stage == 1) {
		// Larva: a C curled around (0, 0.05); grows plumper.
		vec2 q = p - vec2(0.02, 0.05);
		float ang = atan(q.y, q.x);
		float span = 2.05;
		float a = clamp(ang, -span, span);
		float R = 0.4;
		vec2 on = vec2(cos(a), sin(a)) * R;
		float u = (a + span) / (2.0 * span);
		float thick = mix(0.2, 0.36, sin(u * 3.14159)) * mix(0.85, 1.1, t) * (1.0 - 0.12 * hunger);
		d = length(q - on) - thick;
		g = (q - on) / max(thick, 0.01);
		half_thick = thick;
		// Segments as rings across the body.
		detail = 0.5 + 0.5 * cos(a * 7.5);
		base = mix(vec3(0.97, 0.95, 0.86), vec3(0.86, 0.85, 0.78), hunger);
		gloss = 0.8 - 0.4 * hunger;
		// Head capsule at the end of the curl.
		vec2 hc = vec2(cos(span), sin(span)) * R;
		float hd = length(q - hc) - 0.15;
		if (hd < d) {
			d = hd;
			g = (q - hc) / 0.15;
			half_thick = 0.15;
			base = vec3(0.78, 0.55, 0.3);
			detail = 1.0;
		}
	} else {
		// Pupa and callow: a folded worker, head forward (+x).
		float ab = sd_ellipse(p, vec2(-0.34, 0.0), vec2(0.36, 0.27));
		float th = sd_ellipse(p, vec2(0.14, 0.0), vec2(0.2, 0.15));
		float hd = sd_ellipse(p, vec2(0.46, 0.0), vec2(0.15, 0.14));
		d = min(min(ab, th), hd);
		half_thick = 0.25;
		g = ab < th && ab < hd ? (p - vec2(-0.34, 0.0)) / vec2(0.36, 0.27) :
				(th < hd ? (p - vec2(0.14, 0.0)) / vec2(0.2, 0.15) : (p - vec2(0.46, 0.0)) / vec2(0.15, 0.14));
		// Legs and antennae pressed along the body.
		float limbs = 1e5;
		for (int s = -1; s <= 1; s += 2) {
			float fs = float(s);
			limbs = min(limbs, sd_segment(p, vec2(0.2, 0.1 * fs), vec2(-0.25, 0.21 * fs)) - 0.03);
			limbs = min(limbs, sd_segment(p, vec2(0.12, 0.12 * fs), vec2(-0.5, 0.16 * fs)) - 0.028);
			limbs = min(limbs, sd_segment(p, vec2(0.52, 0.08 * fs), vec2(0.05, 0.19 * fs)) - 0.022);
		}
		float mature = stage == 3 ? 1.0 : t;
		vec3 pale = vec3(0.97, 0.93, 0.8);
		vec3 tanned = mix(v_color.rgb, vec3(0.93, 0.8, 0.6), 0.35);
		base = mix(pale, tanned, smoothstep(0.35, 1.0, mature));
		gloss = 0.25;
		// Limbs a touch darker than the body, drawn over it.
		detail = 1.0 - smoothstep(-aa, aa, limbs);
		// Eyes darken first.
		float eyes = min(length(p - vec2(0.5, 0.1)), length(p - vec2(0.5, -0.1))) - 0.045;
		float eye_dark = smoothstep(0.1, 0.4, mature);
		detail = max(detail, (1.0 - smoothstep(-aa, aa, eyes)) * (1.0 + eye_dark));
		if (stage == 3) {
			// The casing splits: a paler rim around the young worker.
			float casing = sd_ellipse(p, vec2(-0.05, 0.0), vec2(0.78, 0.36));
			float rim = abs(casing) - 0.03;
			d = min(d, rim);
			base = mix(base, vec3(0.9, 0.72, 0.5), 0.5);
		}
	}

	float a = 1.0 - smoothstep(-aa, aa, d);
	if (a <= 0.0) {
		// Soft contact shadow, offset away from the light.
		vec2 ps = p + Lw * 0.12;
		float sh = 0.0;
		if (stage == 0) {
			sh = sd_ellipse(ps, vec2(0.0), vec2(0.62, 0.44));
		} else if (stage == 1) {
			sh = length(ps - vec2(0.02, 0.05)) - 0.72;
		} else {
			sh = sd_ellipse(ps, vec2(-0.05, 0.0), vec2(0.75, 0.3));
		}
		float s = (1.0 - smoothstep(-0.05, 0.12, sh)) * 0.35 * v_color.a;
		COLOR = vec4(0.0, 0.0, 0.0, s);
	} else {
		vec3 n = dome(g, d, half_thick);
		float lambert = clamp(dot(n, L), 0.0, 1.0);
		float spec = pow(clamp(dot(n, normalize(L + vec3(0.0, 0.0, 1.0))), 0.0, 1.0), 30.0) * gloss;
		vec3 col = base * (0.72 + 0.38 * lambert);
		if (stage == 1) {
			col *= 1.0 - 0.13 * detail;
		} else if (stage >= 2) {
			col = mix(col, col * 0.62, clamp(detail, 0.0, 1.0));
			col = mix(col, vec3(0.12, 0.08, 0.06), clamp(detail - 1.0, 0.0, 1.0));
		}
		col += vec3(spec * 0.8);
		// Dirt: a fuzz of small grey-green dots.
		vec2 fc = UV * 14.0 + look * 0.37;
		vec2 cell = floor(fc);
		float dot_d = length(fract(fc) - 0.5 - (vec2(hash(cell + 3.0), hash(cell + 9.0)) - 0.5) * 0.4);
		float fuzz = step(1.0 - dirt * 0.75, hash(cell + look)) * (1.0 - smoothstep(0.18, 0.32, dot_d));
		col = mix(col, vec3(0.5, 0.52, 0.42), fuzz * dirt * 0.85);
		COLOR = vec4(col, a * v_color.a);
	}
}
