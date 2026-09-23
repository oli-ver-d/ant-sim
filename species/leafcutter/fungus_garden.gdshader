shader_type canvas_item;
// Cutaway of a leafcutter nest, seen from the side: the ground surface with
// its mound, soil strata, tunnels, chambers, and the fungus garden inside
// them. Coordinates are local pixels of the view (UV * view_size).
//
// Chambers and tunnels are signed distance shapes (ellipses and capsules);
// the garden is a metaball field of soft lumps (set by FungusCutaway from the
// nest's fungus mass), clipped to the chambers, with a cottony noisy edge.

uniform vec2 view_size = vec2(440.0, 330.0);
uniform float surface_y = 40.0;            // ground line (pixels from the top)
uniform float entrance_x = 220.0;          // x of the entrance (the mound is centred on it)
uniform bool detailed = false;             // large view: lighter cavities, surface litter above ground
uniform float mound_height = 10.0;
uniform vec4 chambers[5];                  // centre xy, radii xy (0 = not dug)
uniform int chamber_count = 1;
uniform vec4 tunnels[5];                   // endpoints a.xy, b.xy
uniform int tunnel_count = 1;
uniform float tunnel_width = 7.0;
uniform vec4 lumps[80];                    // centre xy, radius, unused
uniform int lump_count = 0;
uniform float fresh = 0.0;                 // share of fresh leaf in the garden (green flecks)

uniform vec4 topsoil : source_color = vec4(0.2, 0.13, 0.08, 1.0);
uniform vec4 clay : source_color = vec4(0.4, 0.23, 0.13, 1.0);
uniform vec4 cavity : source_color = vec4(0.06, 0.04, 0.03, 1.0);
uniform vec4 fungus_light : source_color = vec4(0.95, 0.92, 0.84, 1.0);
uniform vec4 fungus_shade : source_color = vec4(0.66, 0.62, 0.54, 1.0);
uniform vec4 leaf_green : source_color = vec4(0.36, 0.56, 0.2, 1.0);
uniform vec4 air : source_color = vec4(0.07, 0.07, 0.08, 1.0);

float hash(vec2 p) {
	// Sine-free hash (Dave Hoskins), as in ground.gdshader.
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 2.03 + vec2(13.7, 7.1);
		a *= 0.5;
	}
	return v;
}

// Approximate signed distance to an axis-aligned ellipse.
float sd_ellipse(vec2 p, vec2 c, vec2 r) {
	vec2 q = (p - c) / r;
	return (length(q) - 1.0) * min(r.x, r.y);
}

float sd_segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void fragment() {
	vec2 p = UV * view_size;

	// Ground line with the entrance mound (a soft bump) over the entrance.
	float cx = entrance_x;
	float bump = exp(-pow((p.x - cx) / (view_size.x * 0.14), 2.0));
	float ground = surface_y - mound_height * bump + (noise(vec2(p.x * 0.08, 0.0)) - 0.5) * 3.0;

	// Hollows: chambers and tunnels (negative inside), plus the entrance shaft.
	float hollow = 1e5;
	for (int k = 0; k < 5; k++) {
		if (k >= chamber_count) break;
		vec4 c = chambers[k];
		if (c.z > 0.5) {
			// Wobbly walls so chambers don't look machined.
			float wob = (noise((p - c.xy) * 0.09 + float(k) * 7.0) - 0.5) * 4.0;
			hollow = min(hollow, sd_ellipse(p, c.xy, c.zw) + wob);
		}
	}
	for (int k = 0; k < 5; k++) {
		if (k >= tunnel_count) break;
		hollow = min(hollow, sd_segment(p, tunnels[k].xy, tunnels[k].zw) - tunnel_width * 0.5);
	}

	vec3 col;
	if (p.y < ground - 0.5) {
		// Above ground: dark backdrop, a touch lighter toward the top. The
		// detailed view has only a thin strip here, under the surface view:
		// dark leaf litter.
		col = air.rgb * (1.1 - 0.2 * UV.y);
		if (detailed) {
			col = topsoil.rgb * (0.55 + 0.35 * fbm(p * 0.15));
		}
	} else if (hollow < 0.0) {
		// The detailed view lights its cavities a little, like a lit nest box,
		// so ants read against them.
		col = detailed ? cavity.rgb * 2.4 + vec3(0.03, 0.02, 0.01) : cavity.rgb;
		// Garden: metaballs of the lumps, clipped to the chambers.
		float field = 0.0;
		// The lump contributing most here, and where p sits on it (-1 top, 1 bottom).
		float best = 0.0;
		float rel_y = 0.0;
		for (int j = 0; j < 80; j++) {
			if (j >= lump_count) break;
			vec4 l = lumps[j];
			vec2 d = p - l.xy;
			float c = l.z * l.z / (dot(d, d) + 1.0);
			field += c;
			if (c > best) {
				best = c;
				rel_y = clamp(d.y / max(l.z, 1.0), -1.0, 1.0);
			}
		}
		// Cottony edge: the threshold wobbles with fine noise.
		float fluff = fbm(p * 0.35) * 0.55 + fbm(p * 0.12 + 3.0) * 0.45;
		float g = field * (0.75 + 0.5 * fluff);
		float garden = smoothstep(0.95, 1.12, g);
		if (garden > 0.0) {
			// Lit from above: each lump is brightest on top and shaded underneath,
			// so the garden reads as a heap of soft balls rather than one mass.
			float under = smoothstep(-0.6, 0.9, rel_y);
			vec3 f = mix(fungus_light.rgb, fungus_shade.rgb, under * 0.75 + (1.0 - fluff) * 0.3);
			// Hyphae: fine bright threads.
			f += vec3(0.05) * smoothstep(0.62, 0.8, noise(p * 0.9));
			// Creases where lumps meet (no single lump dominates there).
			f *= 0.72 + 0.28 * smoothstep(0.3, 0.6, best / max(field, 1e-3));
			// Fresh leaf pulp: small round green specks, more with more fresh leaf.
			vec2 fc = floor(p / 4.0);
			vec2 fp = fc * 4.0 + 0.8 + vec2(hash(fc + 1.7), hash(fc + 9.2)) * 2.4;
			float fleck = step(1.0 - fresh * 0.4, hash(fc)) * (1.0 - smoothstep(0.7, 1.3, distance(p, fp)));
			f = mix(f, leaf_green.rgb * (0.8 + 0.4 * hash(fc + 5.0)), fleck * 0.9);
			col = mix(col, f, garden);
		}
		// Soft shadow along the cavity walls.
		col *= 0.75 + 0.25 * smoothstep(-8.0, 0.0, -abs(hollow + 4.0) + 4.0);
	} else {
		// Soil: dark topsoil grading into reddish clay, with strata and pebbles.
		float depth = clamp((p.y - ground) / (view_size.y - surface_y), 0.0, 1.0);
		col = mix(topsoil.rgb, clay.rgb, smoothstep(0.0, 0.45, depth));
		col *= 0.88 + 0.24 * fbm(vec2(p.x * 0.03, p.y * 0.12));
		vec2 cell = floor(p / 9.0);
		vec2 off = vec2(hash(cell), hash(cell + 3.1)) * 9.0;
		float peb = step(0.965, hash(cell + 7.7)) * (1.0 - smoothstep(1.2, 2.2, distance(p, cell * 9.0 + off)));
		col = mix(col, col * 1.6 + 0.05, peb * 0.6);
		// Darker soil around the hollows (ambient occlusion).
		col *= 1.0 - 0.45 * exp(-max(hollow, 0.0) / 5.0);
		// Surface crust: darker, with a faint light line on top.
		col *= mix(0.7, 1.0, smoothstep(0.0, 5.0, p.y - ground));
		col += vec3(0.08, 0.06, 0.04) * (1.0 - smoothstep(0.0, 1.5, p.y - ground));
	}
	COLOR = vec4(col, 1.0);
}
