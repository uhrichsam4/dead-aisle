// The web build's fullscreen lens pass, line for line (its FRAG, minus the
// tone curve and bloom that Godot's Environment already does): a drifting
// tracking-error line, radial barrel distortion with the edges clamped (no
// zoom-to-fill - that is what makes it read as a GoPro), chromatic
// aberration scaled by radius squared, a cubic vignette, luminance-scaled
// grain, faint scanlines and a sensor flicker.
// `mix_amt` blends the web's CUT_EYES look (0) into CUT_GOPRO (1).
// On top of the web's pass, the action-cam's own faults: a short smear along
// a whip-pan (`cam_blur`, set by player.gd each frame from the look's rate),
// dirt and a thumb smudge on the lens that flare when you face the light,
// and the codec giving up in the shadows - chroma bleeding sideways and
// the blacks going to macroblocks, a little worse while the picture moves.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float mix_amt = 1.0;
uniform float flicker = 0.01;
// the smear over one shutter, in screen UV (top-down); zero when steady
uniform vec2 cam_blur = vec2(0.0);

float hash21(vec2 p) {
	p = fract(p * vec2(443.897541, 397.297363));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// bottom-up uv -> the screen texture's top-down, clamped off the edge
vec2 tuv(vec2 uv) {
	return vec2(clamp(uv.x, 0.001, 0.999), 1.0 - clamp(uv.y, 0.001, 0.999));
}

vec3 lens(vec2 uv, vec2 ca) {
	return vec3(texture(screen_tex, tuv(uv + ca)).r,
		texture(screen_tex, tuv(uv)).g,
		texture(screen_tex, tuv(uv - ca)).b);
}

// a smeared, spotty lens: fixed to the glass, heavier toward the rim
float dirt(vec2 q, float vr) {
	float n = vnoise(q * 3.1) * 0.55 + vnoise(q * 7.3 + 11.0) * 0.3 + vnoise(q * 17.0 + 5.0) * 0.15;
	float m = smoothstep(0.56, 0.8, n);
	float s = vnoise(vec2(q.x * 1.6 + q.y * 1.1, q.y * 8.0 - q.x * 3.0) + 3.7);
	m += smoothstep(0.66, 0.92, s) * 0.45;
	return m * (0.3 + 0.7 * smoothstep(0.15, 0.8, vr));
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
	// camera-motion smear: taps along the turn, centred, only while the
	// player says the lens is swinging fast (a uniform branch: free when still)
	vec2 bdir = vec2(cam_blur.x, -cam_blur.y) * mix(0.35, 1.0, mix_amt);
	if (dot(bdir, bdir) > 1e-8) {
		col = vec3(0.0);
		float wsum = 0.0;
		for (int i = 0; i < 7; i++) {
			float t = float(i) / 6.0 - 0.5;
			float wt = 1.0 - abs(t) * 1.2;
			col += lens(uv + bdir * t, ca) * wt;
			wsum += wt;
		}
		col /= wsum;
	} else {
		col = lens(uv, ca);
	}

	// dirt and a smudge on the glass: a veil and a flare where it catches
	// bright light (the blurred frame behind it), GoPro only
	float vr = length(ctr * asp) / length(0.5 * asp);
	float dm = dirt(SCREEN_UV * asp, vr) * mix_amt;
	vec3 glow = textureLod(screen_tex, tuv(uv), 5.0).rgb;
	col = mix(col, glow, dm * 0.07);
	col += dm * max(glow - 0.55, vec3(0.0)) * 0.55;

	// tiny sensor exposure flicker
	col *= 1.0 + sin(TIME * 13.0) * flicker;

	// vignette (cubic lens falloff)
	col *= 1.0 - vignette * vr * vr * vr;

	// the codec, in the shadows only: chroma smeared sideways, the blacks
	// sliding toward 16 px macroblocks and a few steps of banding
	float lum0 = dot(col, vec3(0.2126, 0.7152, 0.0722));
	float dark = (1.0 - smoothstep(0.025, 0.2, lum0)) * mix_amt;
	float moving = clamp(length(cam_blur) * 40.0, 0.0, 1.0);
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 cb = textureLod(screen_tex, tuv(uv + vec2(px.x * 3.0, 0.0)), 2.0).rgb;
	vec3 bleed = cb - dot(cb, vec3(0.2126, 0.7152, 0.0722)) + lum0;
	col = mix(col, bleed, dark * 0.45);
	vec2 bc = (floor(SCREEN_UV / (px * 16.0)) + 0.5) * px * 16.0;
	vec2 bu = vec2(bc.x, 1.0 - bc.y);
	vec2 bctr = bu - 0.5;
	float br2 = dot(bctr * asp, bctr * asp);
	bu += bctr * (k1 * br2 + k2 * br2 * br2);
	vec3 blk = textureLod(screen_tex, tuv(bu), 3.5).rgb;
	col = mix(col, blk, dark * (0.12 + 0.18 * moving));
	col = mix(col, floor(col * 56.0 + 0.5) / 56.0, dark * 0.6);

	// animated hash grain, luminance-scaled
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	float g = hash21(SCREEN_UV * res + vec2(fract(TIME * 91.7) * 137.0, fract(TIME * 57.3) * 211.0)) - 0.5;
	col += g * grain * mix(0.45, 1.25, lum);

	// faint scanlines
	col *= 1.0 - 0.045 * (0.5 + 0.5 * sin(FRAGCOORD.y * 3.14159265));

	COLOR = vec4(col, 1.0);
}
