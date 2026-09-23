shader_type canvas_item;
// Static earthy ground: deep brown soil with large soft colour variation,
// fine grain, small dark organic specks and scattered pebbles with shading
// and contact shadows. Everything is a function of world position (no time),
// so it compresses well in video and stays put as the camera moves.

uniform vec2 world_size = vec2(1080.0, 1920.0);
uniform float seed = 0.0;  // keep small (0-100): offsets the noise domain
uniform vec4 soil_dark : source_color = vec4(0.13, 0.085, 0.055, 1.0);
uniform vec4 soil_light : source_color = vec4(0.24, 0.165, 0.105, 1.0);
uniform vec4 pebble_color : source_color = vec4(0.4, 0.33, 0.25, 1.0);
uniform vec2 light_dir = vec2(-0.55, -0.85);
// Grid spacing for pebble candidates (world units) and the chance of a pebble per cell.
uniform float pebble_spacing = 46.0;
uniform float pebble_density = 0.16;

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

void fragment() {
	vec2 w = UV * world_size;

	// Soil: large patches, medium clods, fine grain.
	vec2 ws = w + seed * vec2(37.0, 91.0);
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

	// Pebbles: at most one per grid cell, checked in the 3x3 neighbourhood.
	vec2 cell = floor(ws / pebble_spacing);
	vec2 L = normalize(light_dir);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = cell + vec2(float(x), float(y));
			if (hash(c + 5.0) > pebble_density) {
				continue;
			}
			vec2 h = hash2(c);
			vec2 centre = (c + 0.2 + 0.6 * h) * pebble_spacing;
			float r = mix(1.6, 5.0, hash(c + 9.0));
			float ang = hash(c + 2.0) * 6.2831;
			vec2 axis = vec2(cos(ang), sin(ang));
			vec2 d = ws - centre;
			vec2 e = vec2(dot(d, axis), dot(d, vec2(-axis.y, axis.x))) / vec2(r, r * mix(0.6, 0.95, h.x));
			// Contact shadow, offset away from the light.
			vec2 ds = d + L * r * 0.45;
			vec2 es = vec2(dot(ds, axis), dot(ds, vec2(-axis.y, axis.x))) / vec2(r, r * mix(0.6, 0.95, h.x));
			col *= 1.0 - 0.35 * (1.0 - smoothstep(0.8, 1.35, length(es)));
			float inside = 1.0 - smoothstep(0.88, 1.0, length(e));
			if (inside > 0.0) {
				// Dome shading: lighter toward the light.
				float lit = clamp(0.6 - dot(e, vec2(dot(L, axis), dot(L, vec2(-axis.y, axis.x)))) * 0.5, 0.2, 1.0);
				vec3 pc = pebble_color.rgb * mix(0.75, 1.15, hash(c + 4.0)) * (0.55 + 0.6 * lit);
				col = mix(col, pc, inside);
			}
		}
	}
	COLOR = vec4(col, 1.0);
}
