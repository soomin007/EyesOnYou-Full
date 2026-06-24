class_name ThumbCanvas
extends Control

# 과제 제출용 정사각 썸네일 — 포스터가 세로라 크롭이 아니라 별도 정사각 캔버스로 렌더한다.
# VEIL 눈(키 비주얼) + "EYES ON YOU" + "SURVEILLANCE ROGUELITE". PosterCanvas와 같은 색·눈 모티프.
# Poster.gd가 600×600 SubViewport로 그린 뒤 150/300으로 다운스케일 저장한다.

const SZ: float = 600.0

const COL_BG: Color = Color(0.043, 0.048, 0.062)
const COL_VEIL: Color = Color(0.46, 0.86, 1.0)
const COL_WHITE: Color = Color(0.95, 0.96, 0.97)
const COL_DIM: Color = Color(0.50, 0.57, 0.66)

const EYE_C: Vector2 = Vector2(300.0, 228.0)
const EYE_R: float = 130.0
const DIV_Y: float = 470.0

func _ready() -> void:
	size = Vector2(SZ, SZ)
	_build_text()

func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, SZ, SZ), COL_BG, true)
	# 미세 스캔라인
	var y: float = 0.0
	while y < SZ:
		draw_line(Vector2(0.0, y), Vector2(SZ, y), Color(0.46, 0.86, 1.0, 0.016), 1.0)
		y += 4.0
	# 코너 브래킷
	_corners(22.0, 26.0)
	# VEIL 눈
	_draw_eye(EYE_C, EYE_R)

func _corners(fm: float, ln: float) -> void:
	var col: Color = COL_VEIL * Color(1, 1, 1, 0.55)
	var wd: float = 2.0
	draw_line(Vector2(fm, fm), Vector2(fm + ln, fm), col, wd)
	draw_line(Vector2(fm, fm), Vector2(fm, fm + ln), col, wd)
	draw_line(Vector2(SZ - fm, fm), Vector2(SZ - fm - ln, fm), col, wd)
	draw_line(Vector2(SZ - fm, fm), Vector2(SZ - fm, fm + ln), col, wd)
	draw_line(Vector2(fm, SZ - fm), Vector2(fm + ln, SZ - fm), col, wd)
	draw_line(Vector2(fm, SZ - fm), Vector2(fm, SZ - fm - ln), col, wd)
	draw_line(Vector2(SZ - fm, SZ - fm), Vector2(SZ - fm - ln, SZ - fm), col, wd)
	draw_line(Vector2(SZ - fm, SZ - fm), Vector2(SZ - fm, SZ - fm - ln), col, wd)

# ── VEIL 눈 (PosterCanvas._draw_eye 모티프, 좌표만 다름) ──
func _draw_eye(c: Vector2, r: float) -> void:
	var col: Color = COL_VEIL
	for i in 6:
		var f: float = float(i) / 5.0
		draw_circle(c, r * (1.25 - f * 0.5), col * Color(1, 1, 1, 0.018))
	_ring(c, r, 2.0, col * Color(1, 1, 1, 0.55))
	_ring(c, r * 0.82, 1.0, col * Color(1, 1, 1, 0.28))
	for i in 12:
		var ang: float = float(i) / 12.0 * TAU
		var cardinal: bool = (i % 3 == 0)
		var inner: float = r * (0.88 if cardinal else 0.93)
		var outer: float = r * (1.10 if cardinal else 1.04)
		var d: Vector2 = Vector2(cos(ang), sin(ang))
		draw_line(c + d * inner, c + d * outer, col * Color(1, 1, 1, (0.5 if cardinal else 0.3)), (1.5 if cardinal else 1.0), true)
	var gap: float = r * 0.30
	var ch: Color = col * Color(1, 1, 1, 0.22)
	draw_line(c + Vector2(-r * 0.78, 0), c + Vector2(-gap, 0), ch, 1.0, true)
	draw_line(c + Vector2(gap, 0), c + Vector2(r * 0.78, 0), ch, 1.0, true)
	draw_line(c + Vector2(0, -r * 0.78), c + Vector2(0, -gap), ch, 1.0, true)
	draw_line(c + Vector2(0, gap), c + Vector2(0, r * 0.78), ch, 1.0, true)
	var sweep: float = -2.25
	var trail_n: int = 18
	for i in trail_n:
		var f: float = float(i) / float(trail_n)
		var ang0: float = sweep - f * 0.9
		draw_arc(c, r * 0.82, ang0 - 0.06, ang0, 4, col * Color(1, 1, 1, (1.0 - f) * 0.5), 2.0, true)
	var sd: Vector2 = Vector2(cos(sweep), sin(sweep))
	draw_line(c, c + sd * r * 0.82, col * Color(1, 1, 1, 0.7), 1.5, true)
	var pulse: float = 0.62
	var pupil_r: float = r * 0.26 * (0.92 + 0.08 * pulse)
	for i in 5:
		var f: float = float(i) / 4.0
		var rr: float = pupil_r * (2.4 - f * 1.4)
		draw_circle(c, rr, col * Color(1, 1, 1, 0.06))
	draw_circle(c, pupil_r, col * Color(1, 1, 1, 0.45 + 0.25 * pulse))
	_ring(c, pupil_r, 1.5, col * Color(1, 1, 1, 0.8))
	draw_circle(c + Vector2(-pupil_r * 0.3, -pupil_r * 0.3), pupil_r * 0.22, Color(0.9, 0.98, 1.0, 0.7))

func _ring(center: Vector2, radius: float, width: float, col: Color) -> void:
	draw_arc(center, radius, 0.0, TAU, 64, col, width, true)

func _build_text() -> void:
	# 아이콘(VEIL 눈) + 제목만. 부제는 군더더기라 제거.
	_label("EYES ON YOU", Vector2(0.0, 424.0), SZ, 64, COL_WHITE, HORIZONTAL_ALIGNMENT_CENTER)

func _label(txt: String, pos: Vector2, w: float, font_size: int, col: Color, align: int) -> void:
	var l: Label = Label.new()
	l.text = txt
	l.position = pos
	l.size = Vector2(w, 0.0)
	l.custom_minimum_size = Vector2(w, 0.0)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = align
	add_child(l)
