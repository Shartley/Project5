shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;

// The light inside a gate portal: a dark core with swirling bands of colour that drift toward the
// centre. Drawn on a quad stretched to the oval opening; everything outside the oval is discarded.

uniform vec4 core_color : source_color = vec4(0.004, 0.012, 0.03, 1.0);
uniform vec4 glow_color : source_color = vec4(0.247, 0.722, 1.0, 1.0); // System Blue; Warning Red for Red gates
uniform float intensity : hint_range(0.0, 6.0) = 2.4;
uniform float swirl_speed : hint_range(0.0, 2.0) = 0.25;
uniform float twist : hint_range(0.0, 4.0) = 1.6;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float t = TIME * swirl_speed;
	float a = atan(p.y, p.x) / 6.28318;
	vec2 suv = vec2(a + t + r * twist * 0.5, r * 1.2 - t * 0.6);
	float n1 = texture(noise_tex, suv).r;
	float n2 = texture(noise_tex, suv * vec2(2.0, 1.7) + vec2(-t * 0.8, t * 0.3)).r;
	float bands = smoothstep(0.42, 0.85, n1 * 0.7 + n2 * 0.45);
	float rim = smoothstep(0.55, 0.98, r);
	float pull = 1.0 - smoothstep(0.0, 0.7, r);              // the dark centre that pulls you in
	float glow = clamp(bands * (0.3 + rim) + rim * rim * 0.8, 0.0, 1.0) * (1.0 - pull * 0.75);
	ALBEDO = mix(core_color.rgb, glow_color.rgb * intensity, glow);
}
