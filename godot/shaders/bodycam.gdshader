// The web build's fullscreen lens pass, line for line (its FRAG, minus the
// tone curve and bloom that Godot's Environment already does): a drifting
// tracking-error line, radial barrel distortion with the edges clamped (no
// zoom-to-fill - that is what makes it read as a GoPro), chromatic
// aberration scaled by radius squared, a cubic vignette, luminance-scaled
// grain, faint scanlines and a sensor flicker.
// `mix_amt` blends the web's CUT_EYES look (0) into CUT_GOPRO (1).
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float mix_amt = 1.0;
uniform float flicker = 0.01;

float hash21(vec2 p) {
	p = fract(p * vec2(443.897541, 397.297363));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

void fragment() {
	// CUT_EYES -> CUT_GOPRO
	float k1 = mix(0.012, 0.16, mix_amt);
	float k2 = mix(0.0, 0.04, mix_amt);
	float aberration = mix(0.05, 0.45, mix_amt);
	float vignette = mix(0.10, 0.40, mix_amt);
	float grain = mix(0.03, 0.11, mix_amt);

	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	// three.js vUv runs bottom-up; SCREEN_UV runs top-down
	vec2 uv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y);
	vec2 asp = vec2(res.x / res.y, 1.0);
	vec2 ctr = uv - 0.5;

	// drifting horizontal jitter line (tracking error)
	float band_y = fract(TIME * 0.063) * 1.3 - 0.15;
	float bd = uv.y - band_y;
	float band = exp(-bd * bd * 7000.0);
	uv.x += band * (hash21(vec2(floor(TIME * 22.0), floor(uv.y * 64.0))) - 0.5) * 0.0075;

	// radial barrel distortion (aspect-corrected radius)
	float r2 = dot(ctr * asp, ctr * asp);
	uv += ctr * (k1 * r2 + k2 * r2 * r2);

	// chromatic aberration, scaled by radius squared
	vec2 ca = ctr * r2 * aberration * 0.013;
	vec3 col;
	col.r = texture(screen_tex, vec2(clamp(uv.x + ca.x, 0.001, 0.999), 1.0 - clamp(uv.y + ca.y, 0.001, 0.999))).r;
	col.g = texture(screen_tex, vec2(clamp(uv.x, 0.001, 0.999), 1.0 - clamp(uv.y, 0.001, 0.999))).g;
	col.b = texture(screen_tex, vec2(clamp(uv.x - ca.x, 0.001, 0.999), 1.0 - clamp(uv.y - ca.y, 0.001, 0.999))).b;

	// tiny sensor exposure flicker
	col *= 1.0 + sin(TIME * 13.0) * flicker;

	// vignette (cubic lens falloff)
	float vr = length(ctr * asp) / length(0.5 * asp);
	col *= 1.0 - vignette * vr * vr * vr;

	// animated hash grain, luminance-scaled
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	float g = hash21(SCREEN_UV * res + vec2(fract(TIME * 91.7) * 137.0, fract(TIME * 57.3) * 211.0)) - 0.5;
	col += g * grain * mix(0.45, 1.25, lum);

	// faint scanlines
	col *= 1.0 - 0.045 * (0.5 + 0.5 * sin(FRAGCOORD.y * 3.14159265));

	COLOR = vec4(col, 1.0);
}
