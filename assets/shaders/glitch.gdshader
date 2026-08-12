shader_type canvas_item;

// 화면 글리치 — 가로 슬라이스 어긋남 + RGB 분리(색수차) + 블록 노이즈 + 스캔라인.
// intensity(0~1)로 강도, seed로 프레임별 패턴을 구동(스크립트가 트윈/틱).
// 광과민성 기준(known_issues): 휘도 반전·백색 플래시 없음 — 변위와 색 분리 중심.
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = seed;
	// 가로 슬라이스 — 불규칙 밴드 일부만 좌우로 찢는다(전부 밀면 노이즈로 뭉개짐).
	float band_count = mix(9.0, 28.0, hash(vec2(t, 1.0)));
	float band = floor(uv.y * band_count);
	if (hash(vec2(band, t + 7.0)) > 0.55) {
		uv.x += (hash(vec2(band, t)) - 0.5) * 0.24 * intensity;
	}
	// 드물게 세로 롤 — 밴드 하나가 위아래로도 미끄러짐.
	if (hash(vec2(band, t + 13.0)) > 0.90) {
		uv.y += (hash(vec2(band, t + 3.0)) - 0.5) * 0.06 * intensity;
	}
	// RGB 분리(색수차).
	float ca = 0.009 * intensity;
	float r = texture(screen_tex, uv + vec2(ca, 0.0)).r;
	float g = texture(screen_tex, uv).g;
	float b = texture(screen_tex, uv - vec2(ca, 0.0)).b;
	vec3 col = vec3(r, g, b);
	// 블록 노이즈 — 드문 사각 셀을 바이올렛으로 물들임(라이벌 축).
	vec2 cell = floor(uv * vec2(24.0, 14.0));
	if (hash(cell + vec2(floor(t * 3.0), t)) > 1.0 - 0.12 * intensity) {
		col = mix(col, vec3(0.55, 0.30, 0.85), 0.5);
	}
	// 스캔라인 — 미세한 어두운 줄(저대비).
	col *= 1.0 - 0.08 * intensity * step(0.5, fract(uv.y * 240.0));
	COLOR = vec4(col, 1.0);
}
