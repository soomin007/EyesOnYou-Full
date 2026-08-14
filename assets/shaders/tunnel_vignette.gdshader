shader_type canvas_item;
render_mode blend_mix;

// 14-2 터널 상하 비네트 — 이전에는 draw_rect 6단 띠로 그려 알파 계단(줄무늬)이 그대로
// 보였다(사용자 지적 2026-08-14). veil_vignette와 같은 방식: 픽셀 단위 smoothstep 감쇠
// + 미세 해시 디더로 8비트 양자화 밴딩까지 흩뜨린다.
uniform float band : hint_range(0.0, 0.5) = 0.16;      // 상/하 비네트 각각의 화면 비율
uniform float strength : hint_range(0.0, 1.0) = 0.34;  // 가장자리 최대 어둡기

float dither(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
}

void fragment() {
	float d = min(UV.y, 1.0 - UV.y);   // 가까운 상/하 가장자리까지의 거리(UV)
	float a = (1.0 - smoothstep(0.0, band, d)) * strength;
	a += dither(FRAGCOORD.xy) / 255.0;
	COLOR = vec4(0.0, 0.0, 0.0, clamp(a, 0.0, 1.0));
}
