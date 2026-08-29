shader_type canvas_item;

// 사망 한 박자(Stage._play_death_beat) · 화면 채도를 amount만큼 빼고 살짝 어둡게.
// 점멸 없음 · 0→amount 램프로만 쓴다(광과민 기준).
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 c = texture(screen_tex, SCREEN_UV);
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 col = mix(c.rgb, vec3(g), amount);
	col *= 1.0 - 0.28 * amount;
	COLOR = vec4(col, 1.0);
}
