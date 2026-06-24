extends Control

# VEIL 인트로 비주얼 — OPERATION PALIMPSEST 진입 시 "연결되며 열리는 감시 조리개/눈".
# 자산 없이 _draw 도형만으로 그린다(백로그: 도형·색 프로토타입). stage 0 인트로에서만 표시
# (Briefing.gd가 visible 제어). 색은 VEIL 시안 계열 — 화면 우측에 "당신을 본다" 정체성을 시각화.
# 등장 시 조리개가 열리고(appear 이징), 스캔 선이 회전하며, 눈동자가 천천히 맥동한다.

const COL_VEIL: Color = Color(0.46, 0.86, 1.0)
const TWO_PI: float = PI * 2.0

var t: float = 0.0        # 누적 시간 — 회전/맥동/스캔라인 구동
var appear: float = 0.0   # 0→1 등장 이징 (조리개 열림)
var degraded: bool = false  # ACT3 시야 붕괴 — 눈이 흐려지고 불안정해짐(서사 연결)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	degraded = GameState.veil_degraded

func _process(delta: float) -> void:
	t += delta
	if appear < 1.0:
		appear = minf(1.0, appear + delta / 0.9)
	degraded = GameState.veil_degraded   # 진행 중 붕괴(begin_degradation) 시작도 실시간 반영
	queue_redraw()

func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x * 0.5, size.y * 0.5) * 0.86
	if r <= 1.0:
		return
	# 시야 붕괴 — 통신 두절/EMP 재머 느낌. 주기적 신호 끊김(드롭아웃) + 위치 지터.
	if degraded:
		if fmod(t * 9.0, 1.0) < 0.16:
			return  # 짧게 화면에서 사라졌다 돌아옴(신호 끊김)
		c += Vector2(randf_range(-2.5, 2.5), randf_range(-2.5, 2.5))
	# easeOutCubic — 등장 알파/스케일.
	var a: float = 1.0 - pow(1.0 - appear, 3.0)
	# 시야 붕괴 후엔 눈이 흐려지고 불안정하게 깜빡인다(VEIL이 잘 못 봄을 브리핑에서도 체감).
	if degraded:
		a *= 0.4 + 0.13 * sin(t * 7.0)
	if a <= 0.001:
		return

	# --- 바깥 링 2겹 + 눈금 ---
	_ring(c, r, 2.0, COL_VEIL * Color(1, 1, 1, 0.55 * a))
	_ring(c, r * 0.82, 1.0, COL_VEIL * Color(1, 1, 1, 0.28 * a))
	# 눈금 — 30°마다 짧은 방사선, 동서남북엔 길게.
	for i in 12:
		var ang: float = float(i) / 12.0 * TWO_PI
		var cardinal: bool = (i % 3 == 0)
		var inner: float = r * (0.88 if cardinal else 0.93)
		var outer: float = r * (1.10 if cardinal else 1.04)
		var dir: Vector2 = Vector2(cos(ang), sin(ang))
		draw_line(c + dir * inner, c + dir * outer, COL_VEIL * Color(1, 1, 1, (0.5 if cardinal else 0.3) * a), 1.5 if cardinal else 1.0, true)

	# --- 십자선 (눈동자 자리엔 간격) ---
	var gap: float = r * 0.30
	var ch: Color = COL_VEIL * Color(1, 1, 1, 0.22 * a)
	draw_line(c + Vector2(-r * 0.78, 0), c + Vector2(-gap, 0), ch, 1.0, true)
	draw_line(c + Vector2(gap, 0), c + Vector2(r * 0.78, 0), ch, 1.0, true)
	draw_line(c + Vector2(0, -r * 0.78), c + Vector2(0, -gap), ch, 1.0, true)
	draw_line(c + Vector2(0, gap), c + Vector2(0, r * 0.78), ch, 1.0, true)

	# --- 회전 스캔 스윕 (잔상 호) ---
	var sweep: float = fmod(t * 1.1, TWO_PI)
	var trail_n: int = 16
	for i in trail_n:
		var f: float = float(i) / float(trail_n)
		var ang0: float = sweep - f * 0.9
		var seg: Color = COL_VEIL * Color(1, 1, 1, (1.0 - f) * 0.5 * a)
		draw_arc(c, r * 0.82, ang0 - 0.06, ang0, 4, seg, 2.0, true)
	# 스윕 선 본체
	var sd: Vector2 = Vector2(cos(sweep), sin(sweep))
	draw_line(c, c + sd * r * 0.82, COL_VEIL * Color(1, 1, 1, 0.7 * a), 1.5, true)

	# --- 눈동자 (조리개 열림 + 맥동) ---
	var pulse: float = 0.5 + 0.5 * sin(t * 1.8)
	var pupil_r: float = r * (0.10 + 0.16 * appear) * (0.92 + 0.08 * pulse)
	# 홍채 글로우 — 바깥에서 안으로 짙어지는 동심원 몇 겹.
	for i in 5:
		var f: float = float(i) / 4.0
		var rr: float = pupil_r * (2.4 - f * 1.4)
		draw_circle(c, rr, COL_VEIL * Color(1, 1, 1, 0.06 * a))
	draw_circle(c, pupil_r, COL_VEIL * Color(1, 1, 1, (0.45 + 0.25 * pulse) * a))
	_ring(c, pupil_r, 1.5, COL_VEIL * Color(1, 1, 1, 0.8 * a))
	# 하이라이트 점 — 시선 느낌.
	draw_circle(c + Vector2(-pupil_r * 0.3, -pupil_r * 0.3), pupil_r * 0.22, Color(0.9, 0.98, 1.0, 0.7 * a))

	# --- 드리프트 스캔라인 (얇은 가로선이 위아래로) ---
	var sy: float = sin(t * 0.7) * r * 0.7
	var half_w: float = sqrt(maxf(0.0, (r * 0.82) * (r * 0.82) - sy * sy))
	draw_line(c + Vector2(-half_w, sy), c + Vector2(half_w, sy), COL_VEIL * Color(1, 1, 1, 0.10 * a), 1.0, true)

func _ring(center: Vector2, radius: float, width: float, col: Color) -> void:
	draw_arc(center, radius, 0.0, TWO_PI, 64, col, width, true)
