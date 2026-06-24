class_name PosterCanvasV2
extends Control

# 과제 전시용 포스터 v2 — 상단은 v1처럼 게임을 소개하고(눈·타이틀·로그라인), 스크린샷 아래에서
# "FULLY AI-GENERATED"를 강조한다. 핵심: 코드·그래픽·음악·효과음 4부문 각각의 기여량(실수치)과
# 생성 AI 모델명을 한 행씩 시원하게 제시(docs/contributions.md 진실). 플레이 피드백 설문 QR/링크도 안내.
# 게임 실제 색·VEIL 눈 모티프·실제 스크린샷을 그대로 쓴다. PosterV2.gd가 SubViewport로 PNG 캡처.

const W: float = 1240.0
const H: float = 1754.0

# ── 게임 아이덴티티 색 (생성 AI별로 색 매칭: Claude=시안 / Suno=앰버 / ElevenLabs=민트) ──
const COL_BG: Color = Color(0.043, 0.048, 0.062)
const COL_VEIL: Color = Color(0.46, 0.86, 1.0)        # VEIL 시안 (브랜드 / Claude)
const COL_WHITE: Color = Color(0.95, 0.96, 0.97)
const COL_GRAY: Color = Color(0.74, 0.79, 0.86)
const COL_DIM: Color = Color(0.50, 0.57, 0.66)
const COL_AMBER: Color = Color(0.96, 0.80, 0.42)      # 앰버 (Suno — 음악)
const COL_SURV: Color = Color(0.58, 0.92, 0.68)       # 민트 (ElevenLabs — 효과음)

const M: float = 100.0
const FM: float = 44.0

# ── 상단 (v1풍 게임 소개) ──
const EYE_C: Vector2 = Vector2(620.0, 156.0)
const EYE_R: float = 84.0
const TITLE_Y: float = 256.0
const SUB_Y: float = 384.0
const LOG_Y: float = 430.0

# ── hero 스크린샷 (큰 한 컷) ──
const HERO_X: float = 120.0
const HERO_Y: float = 510.0
const HERO_W: float = 1000.0
const HERO_H: float = 506.0
const HERO_SHOT: String = "res://poster_out/shots/shot_route_subway.png"
const HERO_CAP: String = "실제 플레이 화면 — VEIL이 위협을 짚어주는 횡스크롤 침투전"

# ── 보조 스크린샷 3컷 ──
const SUP_Y: float = 1052.0
const SUP_W: float = 300.0
const SUP_H: float = 160.0
const SUP_GAP: float = 20.0
const SUPS: Array = [
	["res://poster_out/shots/shot_routemap.png", "맵 선택 · 12개 루트"],
	["res://poster_out/shots/shot_skilltree.png", "스킬 트리 · 3계열"],
	["res://poster_out/shots/shot_route_datacenter.png", "전투 · 적 웨이브"],
]

# ── AI 강조 섹션 (스크린샷 아래 — 메인 메시지) ──
const BADGE_Y: float = 1246.0
const BADGE_W: float = 470.0
const BADGE_H: float = 46.0
const AIROW_Y: float = 1332.0
const AIROW_H: float = 58.0
const AIROW_GAP: float = 6.0
# [accent키, 부문, 상세, "숫자단위"(한 줄), 생성 AI]
const AI_ROWS: Array = [
	["code", "코드", "게임 로직 · 시스템 · 세이브 전부", "17,132줄", "Claude (Anthropic)"],
	["graphic", "그래픽", "캐릭터 · 적 · UI · 이펙트 전부 코드 벡터", "이미지 0장", "Claude (Anthropic)"],
	["music", "음악", "메인 테마 · 스테이지 · 4종 엔딩", "9곡", "Suno"],
	["sound", "효과음", "사격 · 폭발 · 보스 · UI · 환경", "59개", "ElevenLabs"],
]

# ── 피드백 + 푸터 ──
const DIR_Y: float = 1590.0
const FOOT_Y: float = 1616.0
const QR_SZ: float = 94.0
# 구글 폼 설문 링크. 비어 있으면 "준비 중" 표기.
const FEEDBACK_URL: String = "forms.gle/byS8EABJitB9r6z88"
# 실제 QR PNG가 있으면 로드(없으면 placeholder 그림). 링크 확정 후 생성해 넣는다.
const FEEDBACK_QR_PATH: String = "res://poster_out/feedback_qr.png"

var _hero_tex: Texture2D = null
var _sup_tex: Array = []
var _qr_tex: Texture2D = null

func _ready() -> void:
	size = Vector2(W, H)
	_load_shots()
	_build_text()

func _load_shots() -> void:
	_hero_tex = _load_tex(HERO_SHOT)
	_qr_tex = _load_tex(FEEDBACK_QR_PATH)
	var total: float = float(SUPS.size()) * SUP_W + float(SUPS.size() - 1) * SUP_GAP
	var x: float = (W - total) * 0.5
	for entry in SUPS:
		var pair: Array = entry
		var rect: Rect2 = Rect2(x, SUP_Y, SUP_W, SUP_H)
		_sup_tex.append({"tex": _load_tex(str(pair[0])), "rect": rect})
		x += SUP_W + SUP_GAP

func _load_tex(path: String) -> Texture2D:
	var img: Image = Image.new()
	if img.load(path) == OK:
		return ImageTexture.create_from_image(img)
	return null

func _accent_for(key: String) -> Color:
	match key:
		"music":
			return COL_AMBER
		"sound":
			return COL_SURV
		_:
			return COL_VEIL

func _row_rect(i: int) -> Rect2:
	return Rect2(M, AIROW_Y + float(i) * (AIROW_H + AIROW_GAP), W - 2.0 * M, AIROW_H)

func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, W, H), COL_BG, true)
	var y: float = 0.0
	while y < H:
		draw_line(Vector2(0.0, y), Vector2(W, y), Color(0.46, 0.86, 1.0, 0.015), 1.0)
		y += 5.0
	draw_rect(Rect2(FM, FM, W - 2.0 * FM, H - 2.0 * FM), COL_VEIL * Color(1, 1, 1, 0.10), false, 1.0)
	_corner_brackets(FM)
	_draw_eye(EYE_C, EYE_R)
	_draw_hero()
	_draw_sups()
	_draw_badge()
	_draw_ai_rows()
	_draw_feedback()

func _draw_badge() -> void:
	var x: float = (W - BADGE_W) * 0.5
	var rect: Rect2 = Rect2(x, BADGE_Y, BADGE_W, BADGE_H)
	for i in 4:
		var f: float = float(i) / 3.0
		draw_rect(rect.grow(2.0 + f * 7.0), COL_VEIL * Color(1, 1, 1, 0.05 * (1.0 - f)), false, 1.0)
	draw_rect(rect, Color(0.07, 0.13, 0.17, 0.92), true)
	draw_rect(rect, COL_VEIL * Color(1, 1, 1, 0.78), false, 2.0)
	for corner in [[rect.position, Vector2(1, 0), Vector2(0, 1)], [rect.position + Vector2(rect.size.x, 0), Vector2(-1, 0), Vector2(0, 1)], [rect.position + Vector2(0, rect.size.y), Vector2(1, 0), Vector2(0, -1)], [rect.position + rect.size, Vector2(-1, 0), Vector2(0, -1)]]:
		var c: Vector2 = corner[0]
		draw_line(c, c + (corner[1] as Vector2) * 12.0, COL_VEIL, 2.5)
		draw_line(c, c + (corner[2] as Vector2) * 12.0, COL_VEIL, 2.5)

func _draw_hero() -> void:
	var rect: Rect2 = Rect2(HERO_X, HERO_Y, HERO_W, HERO_H)
	for i in 4:
		var f: float = float(i) / 3.0
		draw_rect(rect.grow(2.0 + f * 6.0), COL_VEIL * Color(1, 1, 1, 0.06 * (1.0 - f)), false, 1.0)
	draw_rect(rect, Color(0.06, 0.07, 0.09), true)
	if _hero_tex != null:
		draw_texture_rect(_hero_tex, rect, false)
	draw_rect(rect, COL_VEIL * Color(1, 1, 1, 0.6), false, 2.0)
	_rect_corners(rect, 26.0, COL_VEIL)

func _draw_sups() -> void:
	for item in _sup_tex:
		var d: Dictionary = item
		var rect: Rect2 = d["rect"]
		var tex: Texture2D = d["tex"]
		draw_rect(rect, Color(0.06, 0.07, 0.09), true)
		if tex != null:
			draw_texture_rect(tex, rect, false)
		draw_rect(rect, COL_VEIL * Color(1, 1, 1, 0.5), false, 1.5)
		_rect_corners(rect, 13.0, COL_VEIL)

func _draw_ai_rows() -> void:
	for i in AI_ROWS.size():
		var row: Array = AI_ROWS[i]
		var accent: Color = _accent_for(str(row[0]))
		var r: Rect2 = _row_rect(i)
		draw_rect(r, Color(0.085, 0.105, 0.14, 0.92), true)
		draw_rect(r, accent * Color(1, 1, 1, 0.28), false, 1.0)
		# 좌측 액센트 바
		draw_rect(Rect2(r.position.x, r.position.y, 4.0, r.size.y), accent, true)
		# 아이콘
		_row_icon(str(row[0]), Vector2(r.position.x + 36.0, r.position.y + r.size.y * 0.5), 14.0, accent)

func _row_icon(key: String, c: Vector2, r: float, accent: Color) -> void:
	match key:
		"graphic":
			_icon_vector(c, r, accent)
		"music":
			_icon_wave(c, r, accent)
		"sound":
			_icon_speaker(c, r, accent)
		_:
			_icon_code(c, r, accent)

func _icon_code(c: Vector2, r: float, col: Color) -> void:
	draw_polyline(PackedVector2Array([
		c + Vector2(-r * 0.35, -r * 0.7), c + Vector2(-r, 0), c + Vector2(-r * 0.35, r * 0.7)]), col, 2.0, true)
	draw_polyline(PackedVector2Array([
		c + Vector2(r * 0.35, -r * 0.7), c + Vector2(r, 0), c + Vector2(r * 0.35, r * 0.7)]), col, 2.0, true)
	draw_line(c + Vector2(-r * 0.18, r * 0.6), c + Vector2(r * 0.18, -r * 0.6), col * Color(1, 1, 1, 0.85), 2.0, true)

func _icon_vector(c: Vector2, r: float, col: Color) -> void:
	# 벡터 그래픽 — 다각형 윤곽 + 꼭짓점 앵커(펜툴 노드)
	var pts: Array = [c + Vector2(-r * 0.8, r * 0.6), c + Vector2(0, -r * 0.85), c + Vector2(r * 0.85, r * 0.2), c + Vector2(r * 0.2, r * 0.8)]
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		draw_line(a, b, col * Color(1, 1, 1, 0.8), 1.6, true)
	for p in pts:
		var pv: Vector2 = p
		draw_rect(Rect2(pv.x - 2.2, pv.y - 2.2, 4.4, 4.4), col, true)

func _icon_wave(c: Vector2, r: float, col: Color) -> void:
	var heights: Array = [0.45, 0.9, 0.6, 1.0, 0.5]
	var n: int = heights.size()
	var step: float = (r * 2.0) / float(n - 1)
	for i in n:
		var hx: float = c.x - r + float(i) * step
		var hh: float = r * float(heights[i])
		draw_line(Vector2(hx, c.y - hh), Vector2(hx, c.y + hh), col, 2.0, true)

func _icon_speaker(c: Vector2, r: float, col: Color) -> void:
	var body: PackedVector2Array = PackedVector2Array([
		c + Vector2(-r, -r * 0.35), c + Vector2(-r * 0.35, -r * 0.35), c + Vector2(r * 0.15, -r * 0.75),
		c + Vector2(r * 0.15, r * 0.75), c + Vector2(-r * 0.35, r * 0.35), c + Vector2(-r, r * 0.35)])
	draw_colored_polygon(body, col * Color(1, 1, 1, 0.85))
	draw_arc(c + Vector2(r * 0.15, 0), r * 0.55, -0.9, 0.9, 10, col, 1.8, true)
	draw_arc(c + Vector2(r * 0.15, 0), r * 0.85, -0.8, 0.8, 12, col * Color(1, 1, 1, 0.7), 1.8, true)

func _draw_feedback() -> void:
	# 우하단 코너에 설문 QR + 안내. (FEEDBACK_QR_PATH 있으면 실제 QR, 없으면 placeholder)
	var qx: float = W - M - QR_SZ
	var qy: float = FOOT_Y - 12.0
	var rect: Rect2 = Rect2(qx, qy, QR_SZ, QR_SZ)
	# 흰 배경(quiet zone) + QR을 살짝 안쪽으로 — 스캔 안정성.
	draw_rect(rect, Color(0.96, 0.97, 0.98, 1.0), true)
	if _qr_tex != null:
		var pad: float = QR_SZ * 0.06
		draw_texture_rect(_qr_tex, Rect2(rect.position + Vector2(pad, pad), rect.size - Vector2(pad * 2.0, pad * 2.0)), false)
	else:
		_qr_placeholder(rect)
	draw_rect(rect, COL_VEIL * Color(1, 1, 1, 0.6), false, 1.5)

func _qr_placeholder(rect: Rect2) -> void:
	# QR finder 패턴(세 모서리 사각) — "여기 QR이 들어간다"가 한눈에 읽히게.
	var dark: Color = Color(0.07, 0.09, 0.12)
	var fs: float = rect.size.x * 0.26
	for corner in [rect.position, rect.position + Vector2(rect.size.x - fs, 0), rect.position + Vector2(0, rect.size.y - fs)]:
		var c: Vector2 = corner
		draw_rect(Rect2(c.x + 4, c.y + 4, fs, fs), dark, false, 3.0)
		draw_rect(Rect2(c.x + 4 + fs * 0.3, c.y + 4 + fs * 0.3, fs * 0.4, fs * 0.4), dark, true)
	# 가운데 성긴 모듈(장식)
	for gx in range(3):
		for gy in range(3):
			if (gx + gy) % 2 == 0:
				draw_rect(Rect2(rect.position.x + rect.size.x * 0.45 + float(gx) * 7.0, rect.position.y + rect.size.y * 0.5 + float(gy) * 7.0, 5.0, 5.0), dark, true)

# ── VEIL 눈 ──
func _draw_eye(c: Vector2, r: float) -> void:
	var col: Color = COL_VEIL
	for i in 6:
		var hf: float = float(i) / 5.0
		draw_circle(c, r * (1.34 - hf * 0.5), col * Color(1, 1, 1, 0.032 * (1.0 - hf * 0.55)))
	_ring(c, r, 2.0, col * Color(1, 1, 1, 0.55))
	_ring(c, r * 0.82, 1.0, col * Color(1, 1, 1, 0.28))
	for i in 12:
		var ang: float = float(i) / 12.0 * TAU
		var cardinal: bool = (i % 3 == 0)
		var inner: float = r * (0.88 if cardinal else 0.93)
		var outer: float = r * (1.10 if cardinal else 1.04)
		var d: Vector2 = Vector2(cos(ang), sin(ang))
		draw_line(c + d * inner, c + d * outer, col * Color(1, 1, 1, (0.5 if cardinal else 0.3)), (1.5 if cardinal else 1.0), true)
	var sweep: float = -2.25
	var trail_n: int = 18
	for i in trail_n:
		var f: float = float(i) / float(trail_n)
		var ang0: float = sweep - f * 0.9
		draw_arc(c, r * 0.82, ang0 - 0.06, ang0, 4, col * Color(1, 1, 1, (1.0 - f) * 0.5), 2.0, true)
	var sd: Vector2 = Vector2(cos(sweep), sin(sweep))
	draw_line(c, c + sd * r * 0.82, col * Color(1, 1, 1, 0.7), 1.5, true)
	var pupil_r: float = r * 0.27
	for i in 5:
		var f: float = float(i) / 4.0
		var rr: float = pupil_r * (2.4 - f * 1.4)
		draw_circle(c, rr, col * Color(1, 1, 1, 0.06))
	draw_circle(c, pupil_r, col * Color(1, 1, 1, 0.6))
	_ring(c, pupil_r, 1.5, col * Color(1, 1, 1, 0.8))
	draw_circle(c + Vector2(-pupil_r * 0.3, -pupil_r * 0.3), pupil_r * 0.22, Color(0.9, 0.98, 1.0, 0.7))

func _ring(center: Vector2, radius: float, width: float, col: Color) -> void:
	draw_arc(center, radius, 0.0, TAU, 64, col, width, true)

func _rect_corners(rect: Rect2, ln: float, col: Color) -> void:
	var tl: Vector2 = rect.position
	var tr: Vector2 = rect.position + Vector2(rect.size.x, 0)
	var bl: Vector2 = rect.position + Vector2(0, rect.size.y)
	var br: Vector2 = rect.position + rect.size
	draw_line(tl, tl + Vector2(ln, 0), col, 2.0)
	draw_line(tl, tl + Vector2(0, ln), col, 2.0)
	draw_line(tr, tr + Vector2(-ln, 0), col, 2.0)
	draw_line(tr, tr + Vector2(0, ln), col, 2.0)
	draw_line(bl, bl + Vector2(ln, 0), col, 2.0)
	draw_line(bl, bl + Vector2(0, -ln), col, 2.0)
	draw_line(br, br + Vector2(-ln, 0), col, 2.0)
	draw_line(br, br + Vector2(0, -ln), col, 2.0)

func _corner_brackets(fm: float) -> void:
	var col: Color = COL_VEIL * Color(1, 1, 1, 0.55)
	var ln: float = 40.0
	var wd: float = 2.0
	draw_line(Vector2(fm, fm), Vector2(fm + ln, fm), col, wd)
	draw_line(Vector2(fm, fm), Vector2(fm, fm + ln), col, wd)
	draw_line(Vector2(W - fm, fm), Vector2(W - fm - ln, fm), col, wd)
	draw_line(Vector2(W - fm, fm), Vector2(W - fm, fm + ln), col, wd)
	draw_line(Vector2(fm, H - fm), Vector2(fm + ln, H - fm), col, wd)
	draw_line(Vector2(fm, H - fm), Vector2(fm, H - fm - ln), col, wd)
	draw_line(Vector2(W - fm, H - fm), Vector2(W - fm - ln, H - fm), col, wd)
	draw_line(Vector2(W - fm, H - fm), Vector2(W - fm, H - fm - ln), col, wd)

# ── 텍스트 ──
func _build_text() -> void:
	# 헤더 키커
	_label("ARCTURUS DYNAMICS  ·  현장 작전 기록", Vector2(M, 68.0), W - 2.0 * M, 16,
		COL_VEIL * Color(1, 1, 1, 0.80), HORIZONTAL_ALIGNMENT_LEFT, false)
	_label("OPERATION PALIMPSEST", Vector2(M, 68.0), W - 2.0 * M, 16,
		COL_DIM, HORIZONTAL_ALIGNMENT_RIGHT, false)
	# 타이틀 + 부제 + 로그라인 (v1풍 게임 소개)
	_label("EYES ON YOU", Vector2(M, TITLE_Y), W - 2.0 * M, 104, COL_WHITE, HORIZONTAL_ALIGNMENT_CENTER, false, 8)
	_label("단 하나의 임무, 네 가지 결말", Vector2(M, SUB_Y), W - 2.0 * M, 32, COL_VEIL, HORIZONTAL_ALIGNMENT_CENTER, false, 5)
	_label("현장 요원인 당신에게, 상황실 AI 'VEIL'이 보이지 않는 위협을 미리 짚어준다.\n그 조언을 따를지 무시할지 — 당신의 선택이 결말과 VEIL의 정체를 가른다.",
		Vector2((W - 1000.0) * 0.5, LOG_Y), 1000.0, 21, COL_GRAY, HORIZONTAL_ALIGNMENT_CENTER, true)
	# hero 캡션
	_label(HERO_CAP, Vector2(HERO_X, HERO_Y + HERO_H + 7.0), HERO_W, 15,
		COL_DIM, HORIZONTAL_ALIGNMENT_CENTER, false)
	# 보조 캡션
	_sup_captions(SUP_Y + SUP_H + 7.0)
	# AI 강조 — 배지 + 부제
	_label("FULLY  AI-GENERATED", Vector2((W - BADGE_W) * 0.5, BADGE_Y + 8.0), BADGE_W, 26,
		COL_VEIL, HORIZONTAL_ALIGNMENT_CENTER, false, 5)
	_ai_row_text()
	# Direction (정직한 분담) — AI 행 바로 아래 한 줄
	_label("DIRECTION  ·  기획 · 창작 방향 · 모든 설계 결정 · 검수  —  김수민 (자유전공학부)",
		Vector2(M, DIR_Y), W - 2.0 * M, 15, COL_DIM, HORIZONTAL_ALIGNMENT_CENTER, false)
	# 푸터 좌측 — 플레이 링크 + 스펙 (가로 폭 [M, 700])
	_label("▶  soomin007.github.io/EyesOnYou", Vector2(M, FOOT_Y + 2.0), 600.0, 23,
		COL_VEIL, HORIZONTAL_ALIGNMENT_LEFT, false)
	_label("8–15분 · Windows PC · 키보드 / 게임패드 · Godot 4.6 · Pretendard(OFL)",
		Vector2(M, FOOT_Y + 38.0), 600.0, 14, COL_DIM, HORIZONTAL_ALIGNMENT_LEFT, false)
	# 푸터 우측 — 피드백 안내 (QR 왼쪽, 좌측 컬럼과 안 겹치게 x=720부터)
	var fb_url: String = FEEDBACK_URL if FEEDBACK_URL != "" else "전시 현장 QR로 안내"
	var fb_x: float = 720.0
	var fb_w: float = (W - M - QR_SZ - 16.0) - fb_x
	_label("플레이 후 한 줄 피드백", Vector2(fb_x, FOOT_Y + 2.0), fb_w, 16,
		COL_VEIL * Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_RIGHT, false)
	_label("초보자가 어디서 막히는지 듣고 있어요", Vector2(fb_x, FOOT_Y + 26.0), fb_w, 13,
		COL_GRAY, HORIZONTAL_ALIGNMENT_RIGHT, false)
	_label("✎ " + fb_url, Vector2(fb_x, FOOT_Y + 46.0), fb_w, 13,
		COL_VEIL * Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_RIGHT, false)

func _sup_captions(cy: float) -> void:
	var i: int = 0
	for entry in SUPS:
		var pair: Array = entry
		var rect: Rect2 = (_sup_tex[i] as Dictionary)["rect"]
		_label(str(pair[1]), Vector2(rect.position.x, cy), SUP_W, 14, COL_DIM, HORIZONTAL_ALIGNMENT_CENTER, false)
		i += 1

func _ai_row_text() -> void:
	for i in AI_ROWS.size():
		var row: Array = AI_ROWS[i]
		var accent: Color = _accent_for(str(row[0]))
		var r: Rect2 = _row_rect(i)
		var x: float = r.position.x
		var cy: float = r.position.y
		# 부문명 (색강조, 큰) + 상세 (같은 줄, 회색)
		_label(str(row[1]), Vector2(x + 58.0, cy + 14.0), 112.0, 25, accent, HORIZONTAL_ALIGNMENT_LEFT, false, 5)
		_label(str(row[2]), Vector2(x + 174.0, cy + 21.0), 372.0, 17, COL_GRAY, HORIZONTAL_ALIGNMENT_LEFT, false)
		# 숫자단위 (색강조, 가장 큰, 한 줄)
		_label(str(row[3]), Vector2(x + 560.0, cy + 11.0), 200.0, 30, accent, HORIZONTAL_ALIGNMENT_LEFT, false, 5)
		# 생성 AI 모델명 (색강조, 우측)
		_label(str(row[4]), Vector2(x + 770.0, cy + 17.0), (W - 2.0 * M) - 770.0 - 14.0, 22,
			accent, HORIZONTAL_ALIGNMENT_RIGHT, false)

func _label(txt: String, pos: Vector2, w: float, font_size: int, col: Color, align: int, wrap: bool, outline: int = 4) -> Label:
	var l: Label = Label.new()
	l.text = txt
	l.position = pos
	l.size = Vector2(w, 0.0)
	l.custom_minimum_size = Vector2(w, 0.0)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", outline)
	l.horizontal_alignment = align
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(l)
	return l
