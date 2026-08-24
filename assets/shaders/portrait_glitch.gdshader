shader_type canvas_item;

// 컷씬 초상 "경계 월경" 글리치 — 초상이 대사 패널 위로 넘어온 부분(edge_y 아래)을
// 가로 슬라이스 어긋남 + RGB 분리 + 화자색 블록 노이즈로, 패널 경계를 뚫고 렌더되는
// 느낌으로 잇는다(2026-08-25 사용자 안). glitch.gdshader(화면용)와 같은 문법.
// 광과민 기준 동일(known_issues): 휘도 반전·백색 플래시 없음 — 변위와 색 분리 중심.
// intensity: 상시 저강도 + 줄 시작 버스트(StoryDialogue가 엔벨로프 구동). seed: 프레임 틱.
uniform float intensity : hint_range(0.0, 1.0) = 0.25;
uniform float seed = 0.0;
uniform float edge_y = 0.733;                        // 패널 윗변이 초상 UV에서 지나는 y
uniform vec3 block_tint = vec3(0.30, 0.75, 1.0);     // 블록·단면 색(화자 축: VEIL 청록/라이벌 보라)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float t = seed;
	// 경계 가중 — 윗변 위 0.12 밴드에서 차오르고, 패널을 덮는 아래쪽은 전부 적용.
	// 초상 상단(얼굴)은 깨끗하게 남는다.
	float w = smoothstep(edge_y - 0.12, edge_y, uv.y);
	float k = intensity * w;
	// 가로 슬라이스 — 불규칙 밴드 일부만 좌우로 어긋남.
	float band = floor(uv.y * 26.0);
	if (hash(vec2(band, t + 7.0)) > 0.6) {
		uv.x += (hash(vec2(band, t)) - 0.5) * 0.10 * k;
	}
	// RGB 분리(색수차) — 알파는 중심 샘플 기준(페더 가장자리 보존).
	float ca = 0.006 * k;
	vec4 cr = texture(TEXTURE, uv + vec2(ca, 0.0));
	vec4 cg = texture(TEXTURE, uv);
	vec4 cb = texture(TEXTURE, uv - vec2(ca, 0.0));
	vec4 col = vec4(cr.r, cg.g, cb.b, cg.a);
	// 경계 단면 — 윗변이 지나는 자리에 화자색 주사선 티(넘어오는 단면의 근거).
	float cut = exp(-abs(uv.y - edge_y) * 90.0) * intensity;
	col.rgb += block_tint * cut * 0.35 * col.a;
	// 드문 블록 노이즈(화자색) — 화면 글리치의 바이올렛 블록과 같은 문법.
	vec2 cell = floor(uv * vec2(20.0, 12.0));
	if (hash(cell + vec2(floor(t * 3.0), t)) > 1.0 - 0.10 * k) {
		col.rgb = mix(col.rgb, block_tint * col.a, 0.45);
	}
	COLOR = col;
}
