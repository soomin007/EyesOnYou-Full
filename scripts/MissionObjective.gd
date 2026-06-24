extends Control

# 미션 브리핑 목표물 아이콘 — 회수 대상(핵심 데이터 드라이브)을 보안 링·조준 브래킷과 함께.
# 자산 없이 _draw 도형. stage 0 인트로에서 대사 박스의 빈 오른쪽 자리에 표시.
# 지형 함의 없이 "무엇을 빼오는가"만 보여준다(수직 단면은 횡스크롤과 안 맞아 폐기).
# 색: 보안 링/조준은 VEIL 시안, 드라이브 코어는 따뜻한 호박색(전리품 강조). 회전·맥동으로 생동.

const COL_VEIL: Color = Color(0.46, 0.86, 1.0)
const COL_CORE: Color = Color(1.0, 0.74, 0.42)
const TWO_PI: float = PI * 2.0

var t: float = 0.0
var appear: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	t += delta
	if appear < 1.0:
		appear = minf(1.0, appear + delta / 1.0)
	queue_redraw()

func _draw() -> void:
	var a: float = 1.0 - pow(1.0 - appear, 3.0)
	if a <= 0.001 or size.x < 30.0 or size.y < 30.0:
		return
	var c: Vector2 = Vector2(size.x * 0.5, size.y * 0.46)
	var r: float = minf(size.x * 0.5, size.y * 0.5) * 0.74
	var col: Color = COL_VEIL * Color(1, 1, 1, a)
	var faint: Color = COL_VEIL * Color(1, 1, 1, 0.3 * a)

	# 보안 링 — 동심원 2겹 + 회전 점선 링
	draw_arc(c, r, 0.0, TWO_PI, 48, COL_VEIL * Color(1, 1, 1, 0.4 * a), 1.5, true)
	draw_arc(c, r * 0.78, 0.0, TWO_PI, 40, faint, 1.0, true)
	var spin: float = fmod(t * 0.6, TWO_PI)
	var seg: int = 24
	for i in seg:
		if i % 2 == 0:
			var a0: float = spin + float(i) / float(seg) * TWO_PI
			draw_arc(c, r * 0.90, a0, a0 + TWO_PI / float(seg) * 0.7, 4, COL_VEIL * Color(1, 1, 1, 0.55 * a), 1.5, true)

	# 조준 브래킷 — 네 귀퉁이 ㄱ자
	var br: float = r * 1.16
	var bl: float = r * 0.34
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner: Vector2 = c + Vector2(sx * br, sy * br)
			draw_line(corner, corner - Vector2(sx * bl, 0.0), col, 1.5, true)
			draw_line(corner, corner - Vector2(0.0, sy * bl), col, 1.5, true)

	# 데이터 드라이브 — 중앙 둥근 직사각형 + 데이터 슬랫 + 맥동 코어
	var pulse: float = 0.5 + 0.5 * sin(t * 2.0)
	var dw: float = r * 0.92
	var dh: float = r * 0.66
	var rect := Rect2(c - Vector2(dw * 0.5, dh * 0.5), Vector2(dw, dh))
	draw_rect(rect, Color(0.06, 0.08, 0.10, 0.9 * a), true)
	draw_rect(rect, COL_CORE * Color(1, 1, 1, a), false, 1.5)
	# 데이터 슬랫(가로선 3줄)
	for i in 3:
		var sy2: float = rect.position.y + dh * (0.28 + 0.22 * float(i))
		draw_line(Vector2(rect.position.x + dw * 0.16, sy2), Vector2(rect.position.x + dw * 0.62, sy2),
			COL_CORE * Color(1, 1, 1, 0.55 * a), 1.0, true)
	# 글로우 코어 칩(오른쪽)
	var core: Vector2 = Vector2(rect.position.x + dw * 0.80, c.y)
	draw_circle(core, (r * 0.18 + r * 0.05 * pulse) * a, COL_CORE * Color(1, 1, 1, 0.2 * a))
	draw_circle(core, r * 0.12 * a, COL_CORE * Color(1, 1, 1, (0.6 + 0.3 * pulse) * a))
	draw_circle(core - Vector2(r * 0.03, r * 0.03), r * 0.04 * a, Color(1.0, 0.96, 0.88, 0.8 * a))

	# 라벨 "목표: 핵심 데이터"
	var font: Font = get_theme_default_font()
	if font != null:
		var label: String = "목표: 핵심 데이터"
		var fs: int = 14
		var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(c.x - tw * 0.5, c.y + r * 1.42), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
