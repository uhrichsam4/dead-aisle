// Bodycam / GoPro lens: barrel distortion, chromatic aberration, vignette,
// sensor grain and a faint rolling flicker. Ported from the web build's
// fullscreen pass. `mix_amt` blends from bare eyes (0) to the camera (1) -
// the arrival ramps it as the camera goes on your head.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float k1 = 0.16;
uniform float k2 = 0.04;
uniform float aberration = 0.45;
uniform float vignette = 0.40;
uniform float grain = 0.11;
uniform float flicker = 0.01;
uniform float mix_amt = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	float aspect = res.x / res.y;
	float K1 = k1 * mix_amt;
	float K2 = k2 * mix_amt;

	// barrel distortion in aspect-correct space, zoomed so the corners stay filled
	vec2 c = (uv - 0.5) * vec2(aspect, 1.0);
	float r2 = dot(c, c);
	float f = 1.0 + K1 * r2 + K2 * r2 * r2;
	float edge = 1.0 + K1 * (0.25 * aspect * aspect + 0.25) + K2 * pow(0.25 * aspect * aspect + 0.25, 2.0);
	vec2 d = c * f / edge;
	vec2 duv = d / vec2(aspect, 1.0) + 0.5;

	// chromatic aberration grows toward the edge
	float ca = aberration * mix_amt * 0.0045 * length(c);
	vec2 dir = normalize(c + 1e-5);
	vec3 col;
	col.r = texture(screen_tex, duv + dir * ca).r;
	col.g = texture(screen_tex, duv).g;
	col.b = texture(screen_tex, duv - dir * ca).b;

	// vignette
	float v = smoothstep(1.05, 0.25, length(c * vec2(0.9, 1.0)));
	col *= mix(1.0, v, vignette * mix_amt);

	// grain and a slow exposure flicker
	float n = hash(uv * res + fract(TIME * 61.0) * 100.0);
	col += (n - 0.5) * grain * mix_amt * 0.22;
	col *= 1.0 - flicker * mix_amt * (0.5 + 0.5 * sin(TIME * 23.0));

	COLOR = vec4(col, 1.0);
}
