shader_type canvas_item;
render_mode blend_mix;

// VEIL 화면 비네트 — 중앙 투명 → 가장자리 시안(기본) / 검정·축소(degradation).
// 텍스처 업스케일 대신 픽셀 단위 계산 + 미세 디더로 밴딩(단계 경계)을 없앤다.
// vig: 0=기본(시안 테두리) → 1=붕괴(검정 + 반경 축소). VeilSight가 매 프레임 갱신.

uniform float vig : hint_range(0.0, 1.0) = 0.0;
uniform float time = 0.0;
uniform vec4 calm_color : source_color = vec4(0.46, 0.86, 1.0, 0.10);
uniform vec4 dark_color : source_color = vec4(0.0, 0.0, 0.02, 0.66);
uniform float radius_far = 0.62;   // 기본 — 반경 큼(얇은 가장자리 테두리)
uniform float radius_near = 0.34;  // 붕괴 — 반경 작음(중앙만 보이는 시야 축소)
// 비네트 중심(UV). 기본 화면 중심(0.5,0.5). 붕괴 시 VeilSight가 플레이어 캐릭터 위치로 옮긴다.
uniform vec2 vig_center = vec2(0.5, 0.5);
// 화면 종횡비(가로/세로). UV는 축마다 0~1이라 그대로 재면 타원(가로로 납작)이 된다 → x를 aspect로
// 보정해 픽셀 기준 원에 가깝게. VeilSight가 매 프레임 갱신.
uniform float aspect = 1.777;

// 정렬 안 된 해시 디더 — 밴딩을 1/255 수준 노이즈로 흩뜨려 그라데이션을 매끄럽게.
float dither(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
}

void fragment() {
	vec2 d = UV - vig_center;
	d.x *= aspect;   // 픽셀 기준 원에 가깝게(가로 납작 보정)
	float dist = length(d);
	float radius = mix(radius_far, radius_near, vig);
	// 중앙 투명 → 반경에서 불투명. smoothstep으로 부드러운 falloff.
	float a = smoothstep(0.0, radius, dist);
	vec4 col = mix(calm_color, dark_color, vig);
	// 붕괴 중엔 약한 맥동으로 불안정함.
	float pulse = 1.0 + 0.08 * sin(time * 4.0) * vig;
	a = a * col.a * pulse;
	a += dither(FRAGCOORD.xy) / 255.0;
	COLOR = vec4(col.rgb, clamp(a, 0.0, 1.0));
}
