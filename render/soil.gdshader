shader_type canvas_item;
// An underground layer seen from above: undug soil as a textured, lit mass
// (warped strata, grain, pebbles, fine roots) standing above the dug floor,
// and the tunnels and chambers carved into it with a paler packed floor,
// soft shading near the walls and loose crumbs where digging is under way.
//
// TEXTURE: one texel per cell. R = soil (1) or dug (0); G = work left in a
// soil cell as a share of a full cell (partly bitten cells are the digging
// face). Sampled bicubically with a little noise, as in obstacle.gdshader,
// so outlines are rounded and organic instead of following the cells.
// Everything is a function of world position (no time), so it stays static
// and compresses well in video.

uniform vec2 world_size = vec2(1280.0, 1280.0);
uniform float seed = 0.0;
uniform vec2 light_dir = vec2(-0.55, -0.85);
uniform vec4 soil_dark : source_color = vec4(0.17, 0.11, 0.07, 1.0);
uniform vec4 soil_mid : source_color = vec4(0.3, 0.2, 0.12, 1.0);
uniform vec4 clay : source_color = vec4(0.37, 0.25, 0.15, 1.0);
uniform vec4 sand : source_color = vec4(0.45, 0.36, 0.25, 1.0);
uniform vec4 floor_color : source_color = vec4(0.5, 0.39, 0.27, 1.0);
uniform vec4 pebble_color : source_color = vec4(0.52, 0.47, 0.4, 1.0);

float hash(vec2 p) {
	// Sine-free hash (Dave Hoskins), as in ground.gdshader.
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

vec4 bspline(float v) {
	vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - v;
	vec4 s = n * n * n;
	float x = s.x;
	float y = s.y - 4.0 * s.x;
	float z = s.z - 4.0 * s.y + 6.0 * s.x;
	return vec4(x, y, z, 6.0 - x - y - z) / 6.0;
}

// Bicubic (B-spline) sample using 4 bilinear fetches.
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

// Soil height at uv: the smoothed mask (0 floor .. 1 soil).
float height(sampler2D tex, vec2 uv) {
	return texture_bicubic(tex, uv).r;
}

// Palette pick for a stratum.
vec3 stratum(float pick) {
	return pick < 0.3 ? soil_dark.rgb : (pick < 0.6 ? soil_mid.rgb : (pick < 0.85 ? clay.rgb : sand.rgb));
}

// Undug soil colour at world position w.
vec3 soil_color(vec2 w) {
	// Strata: bands along a slowly warped direction, like a cut through
	// layers; each band keeps its own grain, and neighbours blend only at
	// a narrow, ragged boundary.
	vec2 q = w + vec2(fbm(w / 210.0), fbm(w / 210.0 + 5.2)) * 120.0;
	float band = q.y / 58.0 + fbm(q / 300.0) * 1.8 + (noise(w / 9.0) - 0.5) * 0.12;
	float layer_id = floor(band);
	float t = fract(band);
	vec3 a = stratum(hash(vec2(layer_id, 3.0 + seed)));
	vec3 b = stratum(hash(vec2(layer_id + 1.0, 3.0 + seed)));
	vec3 col = mix(a, b, smoothstep(0.86, 0.98, t));
	// Clods, then fine grain with real contrast so it reads close up.
	col *= 0.8 + 0.34 * fbm(w / 11.0 + 7.0 + layer_id * 3.1);
	col *= 0.9 + 0.2 * noise(w * 0.55 + layer_id);
	// Round specks (grit), one candidate per 2-unit cell.
	vec2 gc = floor(w / 2.0);
	vec2 gf = fract(w / 2.0) - 0.5 - (hash2(gc + 3.0) - 0.5) * 0.4;
	float speck = step(0.88, hash(gc + 7.0)) * (1.0 - smoothstep(0.16, 0.3, length(gf)));
	col = mix(col, col * mix(0.55, 1.4, hash(gc + 1.0)), speck);
	// Fine roots: thin dark wandering lines where a warped noise crosses 0.5.
	float r = fbm(w / 70.0 + 31.0);
	float root = 1.0 - smoothstep(0.0, 0.009, abs(r - 0.5));
	root *= smoothstep(0.45, 0.65, noise(w / 110.0 + 2.0));
	col = mix(col, vec3(0.13, 0.08, 0.045), root * 0.6);
	// Pebbles, one candidate per 30-unit cell, with a contact shadow.
	vec2 L = normalize(light_dir);
	vec2 cell = floor(w / 30.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = cell + vec2(float(x), float(y));
			if (hash(c + 5.0 + seed) > 0.2) {
				continue;
			}
			vec2 centre = (c + 0.2 + 0.6 * hash2(c)) * 30.0;
			float pr = mix(1.1, 3.4, hash(c + 9.0));
			vec2 sq = vec2(pr, pr * mix(0.6, 1.0, hash(c + 1.0)));
			vec2 d = (w - centre) / sq;
			vec2 ds = (w - centre + L * pr * 0.5) / sq;
			col *= 1.0 - 0.3 * (1.0 - smoothstep(0.8, 1.4, length(ds)));
			float inside = 1.0 - smoothstep(0.82, 1.0, length(d));
			float lit = clamp(0.55 - dot(d, L) * 0.5, 0.15, 1.0);
			vec3 pc = mix(pebble_color.rgb, clay.rgb, hash(c + 3.0) * 0.6) * mix(0.55, 0.95, hash(c + 4.0));
			col = mix(col, pc * (0.5 + 0.7 * lit), inside);
		}
	}
	return col;
}

void fragment() {
	vec2 w = UV * world_size;
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec2 L = normalize(light_dir);
	// Irregular outlines: shift the lookup by up to ~2.5 world units of noise.
	vec2 jitter = (vec2(noise(w / 7.0), noise(w / 7.0 + 17.0)) - 0.5) * 5.0 / world_size;
	vec2 uv = UV + jitter;
	vec4 m = texture_bicubic(TEXTURE, uv);
	float soil = smoothstep(0.42, 0.58, m.r);

	// Soil is the raised mass: a normal from the height's gradient lights the
	// rims facing the light and darkens the others.
	float hx = height(TEXTURE, uv + vec2(px.x, 0.0)) - height(TEXTURE, uv - vec2(px.x, 0.0));
	float hy = height(TEXTURE, uv + vec2(0.0, px.y)) - height(TEXTURE, uv - vec2(0.0, px.y));
	vec3 n = normalize(vec3(-hx, -hy, 0.35));
	float lambert = clamp(dot(n, normalize(vec3(-L, 0.9))), 0.0, 1.0);

	// Ambient occlusion on the floor: how much soil is around, near and far.
	float near_soil = 0.0;
	float far_soil = 0.0;
	for (int k = 0; k < 8; k++) {
		float a = float(k) * 0.785398 + 0.39;
		vec2 dir = vec2(cos(a), sin(a));
		near_soil += texture(TEXTURE, uv + dir * px * 1.3).r;
		far_soil += texture(TEXTURE, uv + dir * px * 3.2).r;
	}
	float ao = near_soil / 8.0 * 0.6 + far_soil / 8.0 * 0.4;
	// Shadow cast by the soil onto the floor, away from the light.
	float shadow = texture_bicubic(TEXTURE, uv + L * px * 1.1).r;

	// Floor: packed, paler earth with fine grain and scuffs.
	vec3 fl = floor_color.rgb * (0.9 + 0.18 * fbm(w / 22.0 + 3.0));
	fl *= 1.0 + (noise(w * 1.3) - 0.5) * 0.1;
	fl *= 1.0 - 0.55 * smoothstep(0.1, 0.75, ao);
	fl *= 1.0 - 0.3 * smoothstep(0.3, 0.8, shadow) * (1.0 - soil);

	// Digging face: partly bitten soil (G below a full cell) crumbles, and
	// loose crumbs lie on the floor in front of it.
	float face = (1.0 - smoothstep(0.55, 0.78, m.g)) * smoothstep(0.08, 0.35, m.r);
	vec2 cc = floor(w / 2.2);
	float crumb = step(0.72, hash(cc + 11.0)) * (1.0 - smoothstep(0.25, 0.45, length(fract(w / 2.2) - 0.5)));
	vec3 crumb_col = mix(clay.rgb, sand.rgb, hash(cc + 2.0)) * (0.8 + 0.4 * hash(cc + 6.0));

	vec3 sc = soil_color(w);
	sc *= 0.62 + 0.55 * lambert;
	// Crumbly micro-relief lit from the same side.
	float b0 = fbm(w / 4.5);
	float bx = fbm((w + vec2(0.9, 0.0)) / 4.5) - b0;
	float by = fbm((w + vec2(0.0, 0.9)) / 4.5) - b0;
	vec3 bn = normalize(vec3(-bx, -by, 0.07));
	sc *= 0.82 + 0.32 * clamp(dot(bn, normalize(vec3(-L, 0.8))), 0.0, 1.0);
	// Freshly exposed soil is lighter and moist-looking at the face.
	sc = mix(sc, sc * 1.25 + vec3(0.03, 0.02, 0.0), face * 0.6);
	vec3 col = mix(fl, sc, soil);
	col = mix(col, crumb_col, crumb * face * 0.9);
	// Rim of the tunnel walls: a thin dark crease where soil meets floor.
	float crease = 1.0 - abs(m.r - 0.5) * 2.0;
	col *= 1.0 - 0.25 * smoothstep(0.55, 1.0, crease);
	COLOR = vec4(col, 1.0);
}
