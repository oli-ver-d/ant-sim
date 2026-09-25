shader_type canvas_item;
// Static ground seen from above. Everything is a function of world position
// (no time), so it compresses well in video and stays put as the camera moves.
//
// Materials (weights from GroundMap's textures; soil is what is left over):
//   soil    deep brown, large soft colour variation, fine grain, organic
//           specks and scattered pebbles with contact shadows
//   sand    light fine grain, faint wind ripples in patches, coloured grains
//   gravel  a dense bed of small pebbles over gritty soil
//   moss    green cushions, each a shaded dome, dark gaps between them
//   litter  a mat of dried fragments (tints only; the fragments on top are
//           decals from GroundCoverRenderer)
//   dry     pale cracked clay: plates with curled lit edges, deep and fine cracks
// Material edges blend by a per-material height noise, so gravel pokes through
// sand and moss creeps over soil instead of a plain cross-fade.

uniform vec2 world_size = vec2(1080.0, 1920.0);
uniform float seed = 0.0;  // keep small (0-100): offsets the noise domain
uniform vec2 light_dir = vec2(-0.55, -0.85);  // direction light comes FROM (world, y down)
// Material map (GroundMap): A = sand, gravel, moss, litter; B.r = dry clay.
uniform bool use_materials = false;
uniform sampler2D material_a : filter_linear, repeat_disable;
uniform sampler2D material_b : filter_linear, repeat_disable;

uniform vec4 soil_dark : source_color = vec4(0.13, 0.085, 0.055, 1.0);
uniform vec4 soil_light : source_color = vec4(0.24, 0.165, 0.105, 1.0);
uniform vec4 pebble_color : source_color = vec4(0.4, 0.33, 0.25, 1.0);
// Grid spacing for soil pebble candidates (world units) and the chance of a pebble per cell.
uniform float pebble_spacing = 46.0;
uniform float pebble_density = 0.16;
uniform vec4 sand_dark : source_color = vec4(0.36, 0.28, 0.18, 1.0);
uniform vec4 sand_light : source_color = vec4(0.5, 0.4, 0.27, 1.0);
uniform vec4 gravel_bed : source_color = vec4(0.14, 0.11, 0.08, 1.0);
uniform vec4 gravel_color : source_color = vec4(0.42, 0.39, 0.35, 1.0);
uniform vec4 gravel_warm : source_color = vec4(0.46, 0.35, 0.24, 1.0);
uniform vec4 moss_dark : source_color = vec4(0.08, 0.13, 0.04, 1.0);
uniform vec4 moss_light : source_color = vec4(0.27, 0.36, 0.1, 1.0);
uniform vec4 moss_yellow : source_color = vec4(0.38, 0.38, 0.12, 1.0);
uniform vec4 litter_dark : source_color = vec4(0.12, 0.075, 0.04, 1.0);
uniform vec4 litter_light : source_color = vec4(0.32, 0.21, 0.1, 1.0);
uniform vec4 litter_grey : source_color = vec4(0.26, 0.23, 0.19, 1.0);
uniform vec4 dry_dark : source_color = vec4(0.33, 0.26, 0.2, 1.0);
uniform vec4 dry_light : source_color = vec4(0.45, 0.37, 0.29, 1.0);

float hash(vec2 p) {
	// Sine-free hash (Dave Hoskins): stable across GPUs; sin()-based hashes lose
	// precision for large inputs and show seams between noise cells.
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
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		// Rotate each octave so the value-noise grids don't line up into visible squares.
		p = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 2.03 + vec2(13.7, 7.1);
		a *= 0.5;
	}
	return v;
}

// Voronoi cells (in units of cells): `to_centre` from p to the nearest
// feature point, `edge` the distance to the nearest cell border, `id` a hash
// of the cell.
void voronoi(vec2 p, out vec2 to_centre, out float edge, out float id) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	float md = 8.0;
	vec2 mr = vec2(0.0);
	vec2 mc = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hash2(n + g) - f;
			float d = dot(r, r);
			if (d < md) {
				md = d;
				mr = r;
				mc = n + g;
			}
		}
	}
	// Exact border distance (second pass over a wider neighbourhood).
	edge = 8.0;
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hash2(n + g) - f;
			if (dot(mr - r, mr - r) > 0.00001) {
				edge = min(edge, dot(0.5 * (mr + r), normalize(r - mr)));
			}
		}
	}
	to_centre = mr;
	id = hash(mc + 3.7);
}

// Scattered pebbles: at most one per `spacing` grid cell, `density` the chance
// of one, radius in [r_min, r_max], colour between c1 and c2; domed shading lit
// from L and a contact shadow on the far side.
vec3 pebbles(vec2 ws, vec3 col, float spacing, float density, float r_min, float r_max, vec3 c1, vec3 c2,
		float shadow, vec2 L, float salt) {
	vec2 cell = floor(ws / spacing);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = cell + vec2(float(x), float(y)) + salt;
			if (hash(c + 5.0) > density) {
				continue;
			}
			vec2 h = hash2(c);
			vec2 centre = (c - salt + 0.2 + 0.6 * h) * spacing;
			float r = mix(r_min, r_max, hash(c + 9.0));
			float ang = hash(c + 2.0) * 6.2831;
			vec2 axis = vec2(cos(ang), sin(ang));
			vec2 side = vec2(-axis.y, axis.x);
			vec2 sq = vec2(r, r * mix(0.6, 0.95, h.x));
			vec2 d = ws - centre;
			vec2 e = vec2(dot(d, axis), dot(d, side)) / sq;
			// Contact shadow, offset away from the light.
			vec2 ds = d + L * r * 0.45;
			vec2 es = vec2(dot(ds, axis), dot(ds, side)) / sq;
			col *= 1.0 - shadow * (1.0 - smoothstep(0.8, 1.35, length(es)));
			float inside = 1.0 - smoothstep(0.88, 1.0, length(e));
			if (inside > 0.0) {
				// Dome shading: lighter on the side facing the light.
				float lit = clamp(0.6 + dot(e, vec2(dot(L, axis), dot(L, side))) * 0.5, 0.2, 1.0);
				vec3 pc = mix(c1, c2, hash(c + 1.0)) * mix(0.75, 1.15, hash(c + 4.0)) * (0.55 + 0.6 * lit);
				col = mix(col, pc, inside);
			}
		}
	}
	return col;
}

vec3 soil_look(vec2 ws, vec2 L) {
	// Large patches, medium clods, fine grain.
	float patches = fbm(mat2(vec2(0.96, 0.28), vec2(-0.28, 0.96)) * ws / 260.0);
	float clods = fbm(ws / 38.0 + 11.0);
	// Fine grain as smooth noise (not per-pixel blocks) so it holds up when zoomed in.
	float grain = noise(ws * 0.9) - 0.5;
	vec3 col = mix(soil_dark.rgb, soil_light.rgb, smoothstep(0.15, 0.85, patches * 0.7 + clods * 0.3));
	col *= 1.0 + grain * 0.12;
	// Small round dark organic specks, one candidate per 3x3 unit cell.
	vec2 sc = floor(ws / 3.0);
	float speck = step(0.985, hash(sc + 3.0)) * (1.0 - smoothstep(0.25, 0.4, length(fract(ws / 3.0) - 0.5)));
	col *= 1.0 - speck * 0.35;
	return pebbles(ws, col, pebble_spacing, pebble_density, 1.6, 5.0, pebble_color.rgb, pebble_color.rgb, 0.35, L, 0.0);
}

vec3 sand_look(vec2 ws) {
	vec3 col = mix(sand_dark.rgb, sand_light.rgb, smoothstep(0.25, 0.75, fbm(ws / 170.0 + 3.0)));
	// Wind ripples: warped bands across a slowly turning direction, only in patches.
	float turn = (fbm(ws / 400.0 + 9.0) - 0.5) * 1.2;
	vec2 dir = vec2(cos(1.1 + turn), sin(1.1 + turn));
	float phase = dot(ws, dir) / 6.5 + fbm(ws / 80.0 + 5.0) * 10.0;
	float ripple = sin(phase) + 0.35 * sin(phase * 2.0 + 1.3);
	col *= 1.0 + ripple * 0.045 * smoothstep(0.4, 0.65, fbm(ws / 240.0 + 21.0));
	// Fine grain at two sizes.
	col *= 1.0 + (noise(ws * 1.6) - 0.5) * 0.13 + (noise(ws * 0.5 + 4.0) - 0.5) * 0.07;
	// Scattered dark and pale grains, one candidate per 2x2 unit cell.
	float g = hash(floor(ws / 2.0) + 41.0);
	float dot_mask = 1.0 - smoothstep(0.18, 0.4, length(fract(ws / 2.0) - 0.5));
	col *= 1.0 - step(0.965, g) * dot_mask * 0.4;
	col += step(g, 0.03) * dot_mask * vec3(0.07, 0.065, 0.05);
	return col;
}

vec3 gravel_look(vec2 ws, vec2 L) {
	vec3 col = gravel_bed.rgb * (0.8 + 0.4 * fbm(ws / 50.0 + 13.0)) * (1.0 + (noise(ws * 1.3) - 0.5) * 0.25);
	col = pebbles(ws, col, 5.0, 0.55, 0.8, 1.9, gravel_color.rgb, gravel_warm.rgb, 0.3, L, 71.0);
	col = pebbles(ws, col, 9.0, 0.8, 1.8, 4.2, gravel_color.rgb, gravel_warm.rgb, 0.45, L, 23.0);
	// A few bigger stones.
	return pebbles(ws, col, 26.0, 0.35, 3.5, 6.5, gravel_color.rgb, gravel_warm.rgb, 0.45, L, 131.0);
}

vec3 moss_look(vec2 ws, vec2 L) {
	// Cushions: warped Voronoi cells about 6 units across, each a low dome.
	vec2 warp = vec2(fbm(ws / 24.0), fbm(ws / 24.0 + 5.0)) - 0.5;
	vec2 to_c;
	float edge;
	float id;
	voronoi(ws / 6.5 + warp * 1.3, to_c, edge, id);
	// Dome: the side of the cushion facing the light is brighter.
	float lit = clamp(0.72 + dot(-to_c, L) * 0.55, 0.3, 1.1);
	float gap = 1.0 - smoothstep(0.0, 0.16, edge);
	vec3 col = mix(moss_dark.rgb, moss_light.rgb, 0.3 + 0.55 * id);
	col = mix(col, moss_yellow.rgb, smoothstep(0.55, 0.85, fbm(ws / 140.0 + 2.0)) * 0.6);
	// Fronds: fine bumps lit from the light (height here minus height toward the light).
	vec2 fp = ws * 1.7 + 7.0;
	float f = noise(fp);
	float relief = f - noise(fp + L * 0.6);
	col *= lit * (0.82 + 0.25 * f + 0.9 * relief);
	// Tiny pale capsule tips.
	col += step(0.975, hash(floor(ws / 1.5) + 12.0)) * 0.06 * moss_yellow.rgb;
	return mix(col, moss_dark.rgb * 0.6, gap * 0.55);
}

vec3 litter_look(vec2 ws, vec2 L) {
	// A mat of fragments: cells each tinted from a dry palette, dark gaps between.
	vec2 warp = vec2(fbm(ws / 30.0 + 1.0), fbm(ws / 30.0 + 8.0)) - 0.5;
	vec2 to_c;
	float edge;
	float id;
	voronoi(ws / 7.0 + warp * 1.6, to_c, edge, id);
	vec3 col = mix(litter_dark.rgb, litter_light.rgb, fract(id * 3.1));
	col = mix(col, litter_grey.rgb, step(0.8, id) * 0.7);
	// Fibres along each fragment's own direction.
	float ang = id * 6.2831;
	vec2 fdir = vec2(cos(ang), sin(ang));
	col *= 0.85 + 0.3 * noise(vec2(dot(ws, fdir) * 0.3, dot(ws, vec2(-fdir.y, fdir.x)) * 2.2) + id * 50.0);
	// Curled fragments: lit on the side facing the light.
	col *= 0.9 + 0.2 * clamp(dot(-to_c, L), -1.0, 1.0);
	col = mix(col, litter_dark.rgb * 0.6, (1.0 - smoothstep(0.0, 0.12, edge)) * 0.3);
	// Damp humus showing through in patches.
	return mix(col, soil_dark.rgb * 0.8, smoothstep(0.55, 0.8, fbm(ws / 60.0 + 17.0)) * 0.6);
}

vec3 dry_look(vec2 ws, vec2 L) {
	vec3 col = mix(dry_dark.rgb, dry_light.rgb, smoothstep(0.2, 0.8, fbm(ws / 120.0 + 31.0)));
	col *= 1.0 + (noise(ws * 1.1) - 0.5) * 0.1;
	vec2 warp = vec2(fbm(ws / 40.0 + 3.0), fbm(ws / 40.0 + 12.0)) - 0.5;
	vec2 to_c;
	float edge;
	float id;
	// Plates about 26 units across, cracks between them.
	voronoi(ws / 26.0 + warp * 0.8, to_c, edge, id);
	col *= 0.94 + 0.12 * id;
	// Curled plate edges catch the light on the side facing it.
	float rim = 1.0 - smoothstep(0.03, 0.14, edge);
	col *= 1.0 + rim * clamp(dot(-to_c, L), -1.0, 1.0) * 0.18;
	float aa = max(fwidth(edge), 0.004);
	float crack = 1.0 - smoothstep(0.018, 0.018 + aa * 1.5, edge);
	col = mix(col, dry_dark.rgb * 0.25, crack * 0.9);
	// Fine cracks inside plates, only along some borders.
	vec2 to_c2;
	float edge2;
	float id2;
	voronoi(ws / 8.0 + warp * 2.0 + 40.0, to_c2, edge2, id2);
	float aa2 = max(fwidth(edge2), 0.01);
	float fine = (1.0 - smoothstep(0.02, 0.02 + aa2 * 1.5, edge2)) * step(0.55, noise(ws / 11.0 + 60.0));
	return col * (1.0 - fine * 0.25);
}

void fragment() {
	vec2 w = UV * world_size;
	vec2 ws = w + seed * vec2(37.0, 91.0);
	vec2 L = normalize(light_dir);
	if (!use_materials) {
		COLOR = vec4(soil_look(ws, L), 1.0);
	} else {
		// Ragged material edges: shift the map lookup by a few world units of noise.
		vec2 jitter = (vec2(fbm(ws / 20.0 + 40.0), fbm(ws / 20.0 + 70.0)) - 0.5) * 16.0;
		vec2 uv = (w + jitter) / world_size;
		vec4 a = texture(material_a, uv);
		float dry = texture(material_b, uv).r;
		float soil = max(1.0 - a.r - a.g - a.b - a.a - dry, 0.0);
		// Height blend: each material has its own bumps; the tallest wins near an edge.
		float h[6];
		float wt[6] = {soil, a.r, a.g, a.b, a.a, dry};
		float top = 0.0;
		for (int i = 0; i < 6; i++) {
			h[i] = wt[i] + (noise(ws / 5.0 + float(i) * 17.3) - 0.5) * 0.45 * step(0.001, wt[i]);
			top = max(top, h[i]);
		}
		float total = 0.0;
		for (int i = 0; i < 6; i++) {
			wt[i] = wt[i] > 0.001 ? max(h[i] - top + 0.1, 0.0) : 0.0;
			total += wt[i];
		}
		vec3 col = vec3(0.0);
		if (wt[0] > 0.0) col += soil_look(ws, L) * wt[0];
		if (wt[1] > 0.0) col += sand_look(ws) * wt[1];
		if (wt[2] > 0.0) col += gravel_look(ws, L) * wt[2];
		if (wt[3] > 0.0) col += moss_look(ws, L) * wt[3];
		if (wt[4] > 0.0) col += litter_look(ws, L) * wt[4];
		if (wt[5] > 0.0) col += dry_look(ws, L) * wt[5];
		COLOR = vec4(col / max(total, 1e-4), 1.0);
	}
}
