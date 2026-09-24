shader_type canvas_item;
// Leafcutter fungus gardens seen from above, drawn over the chamber floors
// from the nest's GardenGrid (one texel per garden cell):
//   R  fungus (0-1 = empty-full, up to 1.5 over-full)   G  fresh leaf pulp
//   B  spent material, age and mould (browning)         A  gongylidia
// The garden is a raised spongy mass: a height field from the fungus with
// pores and hyphal strands in it, lit from the shared light direction with
// soft self-shadowing, casting a soft shadow on the floor at its edge. Fresh
// pulp shows as green flecks on top, old material browns, and clusters of
// white gongylidia beads swell where the fungus is healthy. Fine detail
// (pores, beads, flecks) fades with zoom so the whole-nest overview stays
// calm while close-ups show every bead.

uniform vec2 world_size = vec2(1280.0, 1280.0);
uniform vec2 light_dir = vec2(-0.55, -0.85);
uniform vec4 hyphae : source_color = vec4(0.95, 0.94, 0.89, 1.0);
uniform vec4 hyphae_shade : source_color = vec4(0.7, 0.68, 0.62, 1.0);
uniform vec4 spent_color : source_color = vec4(0.5, 0.39, 0.26, 1.0);
uniform vec4 leaf_green : source_color = vec4(0.36, 0.58, 0.2, 1.0);
uniform vec4 bead : source_color = vec4(1.0, 0.99, 0.93, 1.0);

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash2(vec2 p) {
	return vec2(hash(p), hash(p + vec2(19.19, 7.31)));
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

// Distance to the nearest of a jittered grid of points (cellular noise):
// small near pore centres.
float cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 r = o + hash2(i + o) * 0.85 - f;
			d = min(d, dot(r, r));
		}
	}
	return sqrt(d);
}

vec4 bspline(float v) {
	vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - v;
	vec4 s = n * n * n;
	float x = s.x;
	float y = s.y - 4.0 * s.x;
	float z = s.z - 4.0 * s.y + 6.0 * s.x;
	return vec4(x, y, z, 6.0 - x - y - z) / 6.0;
}

vec4 texture_bicubic(sampler2D tex, vec2 uv) {
	vec2 tex_size = vec2(textureSize(tex, 0));
	vec2 inv = 1.0 / tex_size;
	uv = uv * tex_size - 0.5;
	vec2 f = fract(uv);
	uv -= f;
	vec4 xc = bspline(f.x);
	vec4 yc = bspline(f.y);
	vec4 c = uv.xxyy + vec2(-0.5, 1.5).xyxy;
	vec4 s = vec4(xc.xz + xc.yw, yc.xz + yc.yw);
	vec4 o = (c + vec4(xc.yw, yc.yw) / s) * inv.xxyy;
	vec4 s0 = texture(tex, o.xz);
	vec4 s1 = texture(tex, o.yz);
	vec4 s2 = texture(tex, o.xw);
	vec4 s3 = texture(tex, o.yw);
	float sx = s.x / (s.x + s.y);
	float sy = s.z / (s.z + s.w);
	return mix(mix(s3, s2, sx), mix(s1, s0, sx), sy);
}

// Height of the garden at world position w (density from the grid shaped
// by pores and strands), with `detail` (0-1) of the fine structure.
float garden_height(sampler2D tex, vec2 w, float detail) {
	vec4 g = texture_bicubic(tex, w / world_size);
	float dens = g.r * 1.5;
	float lumps = noise(w / 9.0) * 0.5 + noise(w / 4.0) * 0.35;
	// Sponge: rounded bumps between pores at two scales, and fine strands.
	float bumps = (1.0 - cells(w / 2.4)) * 0.6 + (1.0 - cells(w / 1.1)) * 0.4;
	float strands = noise(w * vec2(1.4, 0.4) + noise(w / 4.0) * 3.0);
	float fine = mix(0.7, 0.45 + bumps * 0.45 + strands * 0.15, detail);
	return dens * (0.5 + 0.6 * lumps) * fine * 3.0;
}

void fragment() {
	vec2 w = UV * world_size;
	// World units per screen pixel: fine detail fades out as it gets too
	// small to see (level of detail by zoom).
	float px = length(fwidth(w));
	float detail = 1.0 - smoothstep(0.18, 0.55, px);
	vec4 g = texture_bicubic(TEXTURE, UV);
	float dens = g.r * 1.5;
	// The garden's outline: lumpy and cottony. A blurred density spreads the
	// edge over several units so noise can push it in and out.
	vec2 tp = TEXTURE_PIXEL_SIZE * 2.2;
	float blur = (dens + (texture(TEXTURE, UV + vec2(tp.x, 0.0)).r + texture(TEXTURE, UV - vec2(tp.x, 0.0)).r
			+ texture(TEXTURE, UV + vec2(0.0, tp.y)).r + texture(TEXTURE, UV - vec2(0.0, tp.y)).r) * 1.5) / 5.0;
	float edge_noise = (noise(w / 6.0) - 0.5) * 0.55 + (noise(w / 2.3) - 0.5) * 0.18;
	float cover = smoothstep(0.3, 0.42, blur + edge_noise) * smoothstep(0.02, 0.1, dens);
	vec2 L = normalize(light_dir);
	// Shadow the raised garden casts on the floor beside it.
	float behind = texture_bicubic(TEXTURE, UV + L * 2.5 / world_size).r * 1.5;
	float floor_shadow = smoothstep(0.1, 0.35, behind) * (1.0 - cover) * 0.45;
	if (cover <= 0.0) {
		COLOR = vec4(0.0, 0.0, 0.0, floor_shadow);
	} else {
		float e = 0.6;
		float h = garden_height(TEXTURE, w, detail);
		float hx = garden_height(TEXTURE, w + vec2(e, 0.0), detail) - h;
		float hy = garden_height(TEXTURE, w + vec2(0.0, e), detail) - h;
		vec3 n = normalize(vec3(-hx, -hy, 0.35));
		vec3 L3 = normalize(vec3(-L, 0.75));
		float lambert = clamp(dot(n, L3), 0.0, 1.0);
		// Self-shadowing: a point is shaded if the garden toward the light is higher.
		float toward = garden_height(TEXTURE, w - L * 2.0, detail * 0.5);
		float self_shadow = clamp((toward - h) * 0.5, 0.0, 0.5);
		// Pores read as dark pits close up.
		float pit = (1.0 - smoothstep(0.02, 0.14, cells(w / 2.4))) * detail;
		vec3 col = mix(hyphae_shade.rgb, hyphae.rgb, 0.25 + 0.75 * lambert);
		col *= 1.0 - self_shadow;
		col *= 1.0 - pit * 0.22;
		// A soft sheen on the tops of the bumps.
		col += vec3(0.08) * pow(clamp(dot(n, normalize(L3 + vec3(0.0, 0.0, 1.0))), 0.0, 1.0), 12.0) * detail;
		col *= 0.94 + 0.12 * noise(w / 5.0);
		// Thin garden (a young or dying patch) shows the floor's tone through.
		col = mix(col * 0.8, col, smoothstep(0.2, 0.6, dens));
		// Old, spent or mouldy material browns.
		float brown = smoothstep(0.1, 0.9, g.b);
		vec3 old = spent_color.rgb * (0.7 + 0.45 * noise(w / 2.0));
		col = mix(col, old, brown * 0.85);
		// Fresh leaf pulp on top: green flecks, more where more was planted.
		vec2 fc = floor(w / 1.3);
		float fleck = step(1.0 - clamp(g.g * 1.6, 0.0, 0.85), hash(fc + 17.0));
		float fleck_shape = 1.0 - smoothstep(0.2, 0.48, length(fract(w / 1.3) - 0.5 - (hash2(fc) - 0.5) * 0.3));
		vec3 green = leaf_green.rgb * (0.75 + 0.5 * hash(fc + 3.0));
		col = mix(col, green * (0.7 + 0.4 * lambert), fleck * fleck_shape * mix(0.6, 1.0, detail));
		// A faint green tint where pulp lies thick (reads in the overview).
		col = mix(col, leaf_green.rgb, clamp(g.g, 0.0, 1.0) * 0.18 * (1.0 - detail * 0.5));
		// Gongylidia: clusters of glossy white beads on healthy fungus.
		vec2 bc = floor(w / 2.6);
		float gong = g.a * (1.0 - brown);
		if (hash(bc + 41.0) < gong * 0.8 && detail > 0.02) {
			vec3 bead_col = vec3(0.0);
			float bead_a = 0.0;
			for (int k = 0; k < 4; k++) {
				vec2 centre = (bc + 0.2 + 0.6 * hash2(bc + float(k) * 7.1)) * 2.6;
				float r = mix(0.35, 0.62, hash(bc + float(k) * 3.3));
				vec2 d = (w - centre) / r;
				float inside = 1.0 - smoothstep(0.75, 1.0, length(d));
				if (inside > bead_a) {
					float z = sqrt(max(0.0, 1.0 - dot(d, d)));
					vec3 bn = normalize(vec3(d, z));
					float bl = clamp(dot(bn, L3), 0.0, 1.0);
					float spec = pow(clamp(dot(bn, normalize(L3 + vec3(0.0, 0.0, 1.0))), 0.0, 1.0), 24.0);
					bead_col = bead.rgb * (0.6 + 0.45 * bl) + vec3(spec * 0.6);
					bead_a = inside;
				}
			}
			col = mix(col, bead_col, bead_a * detail);
		} else {
			// In the overview gongylidia read as a brighter sheen.
			col += vec3(0.06) * gong * (1.0 - detail);
		}
		COLOR = vec4(col, cover + floor_shadow * (1.0 - cover));
	}
}
