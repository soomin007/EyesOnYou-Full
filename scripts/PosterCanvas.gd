class_name PosterCanvas
extends Control

# 과제 제출용 게임 소개 포스터 — 인엔진 렌더. 게임의 실제 색·폰트·VEIL 눈(BriefingVisual 모티프)과
# 실제 게임 스크린샷을 함께 써서 화면 아이덴티티와 일치시킨다. _draw로 그래픽(눈/프레임/스샷/엔딩박스/
# 특징 패널/VEIL 대화창), Label 자식으로 텍스트. 세로 포스터(A4 비율 근사, 1240×1754).
# Poster.gd가 SubViewport로 PNG 캡처. 스크린샷은 Screenshotter.gd가 미리 저장해 둔 것을 런타임 로드.

const W: float = 1240.0
const H: float = 1754.0

# ── 게임 아이덴티티 색 ── (파랑 계열 중복을 피해 4셀을 시안/코랄/앰버/민트로 분리)
const COL_BG: Color = Color(0.043, 0.048, 0.062)
const COL_VEIL: Color = Color(0.46, 0.86, 1.0)        # VEIL 시안 (브랜드)
const COL_WHITE: Color = Color(0.95, 0.96, 0.97)
const COL_GRAY: Color = Color(0.74, 0.79, 0.86)
const COL_DIM: Color = Color(0.50, 0.57, 0.66)
const COL_COMBAT: Color = Color(0.97, 0.58, 0.48)     # 코랄 (적/위협)
const COL_AMBER: Color = Color(0.96, 0.80, 0.42)      # 앰버 (스킬/성장)
const COL_SURV: Color = Color(0.58, 0.92, 0.68)       # 민트 (맵/탐험)

const M: float = 100.0
const FM: float = 44.0
const EYE_C: Vector2 = Vector2(620.0, 218.0)
const EYE_R: float = 158.0

# ── 엔딩 행 (수용률 × 전투 성향 → 4결말. EndingResolver.gd 진실) ──
const END_Y: float = 758.0
const END_H: float = 84.0
const END_GAP: float = 18.0
const ENDINGS: Array = [
	["A", "완벽한 도구"],
	["B", "혼자였던 사람"],
	["C", "공생"],
	["D", "유령 임무"],
]

# ── 스크린샷 스트립 (3장, 16:9) ──
const SHOT_Y: float = 904.0
const SHOT_W: float = 336.0
const SHOT_H: float = 189.0
const SHOT_GAP: float = 16.0
const SHOTS: Array = [
	["res://poster_out/shots/shot_routemap.png", "맵 선택 — 위험과 보상"],
	["res://poster_out/shots/shot_skilltree.png", "스킬 트리 — 3계열"],
	["res://poster_out/shots/shot_route_datacenter.png", "전투 — 사격·회피·스킬"],
]

# ── 특징 2×2 (박스는 엔딩/스샷과 같은 좌우 경계 100~1140에 맞춤. FX는 박스 안쪽 패딩 14) ──
const FX_L: float = 114.0
const FX_R: float = 648.0
const FCW: float = 478.0
const FY_1: float = 1170.0
const FY_2: float = 1310.0
const FBOX_H: float = 110.0

# ── VEIL 대화창 ──
const DLG_Y: float = 1428.0
const DLG_H: float = 104.0

var _shot_tex: Array = []  # [{tex, rect}]

func _ready() -> void:
	size = Vector2(W, H)
	_load_shots()
	_build_text()

func _load_shots() -> void:
	var total: float = float(SHOTS.size()) * SHOT_W + float(SHOTS.size() - 1) * SHOT_GAP
	var x: float = (W - total) * 0.5
	for entry in SHOTS:
		var pair: Array = entry
		var path: String = str(pair[0])
		var rect: Rect2 = Rect2(x, SHOT_Y, SHOT_W, SHOT_H)
		var tex: Texture2D = null
		var img: Image = Image.new()
		if img.load(path) == OK:
			tex = ImageTexture.create_from_image(img)
		_shot_tex.append({"tex": tex, "rect": rect})
		x += SHOT_W + SHOT_GAP

func _ending_rect(i: int) -> Rect2:
	var bw: float = (W - 2.0 * M - 3.0 * END_GAP) / 4.0
	var x: float = M + float(i) * (bw + END_GAP)
	return Rect2(x, END_Y, bw, END_H)

func _feat_rect(col: int, row: int) -> Rect2:
	var fx: float = FX_L if col == 0 else FX_R
	var fy: float = FY_1 if row == 0 else FY_2
	return Rect2(fx - 14.0, fy - 18.0, FCW + 28.0, FBOX_H)

func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, W, H), COL_BG, true)
	# 미세 스캔라인 — CRT/감시화면 질감
	var y: float = 0.0
	while y < H:
		draw_line(Vector2(0.0, y), Vector2(W, y), Color(0.46, 0.86, 1.0, 0.015), 1.0)
		y += 5.0
	# 프레임 + 코너 브래킷 — 콘텐츠(M=100)보다 바깥이라 텍스트와 안 겹침
	draw_rect(Rect2(FM, FM, W - 2.0 * FM, H - 2.0 * FM), COL_VEIL * Color(1, 1, 1, 0.10), false, 1.0)
	_corner_brackets(FM)
	# 키 비주얼 — VEIL 눈 (글로우 강화)
	_draw_eye(EYE_C, EYE_R)
	# 엔딩 행
	_draw_endings()
	# 스크린샷
	_draw_shots()
	# 특징 패널 (가독성 박스)
	_draw_feat_panels()
	# VEIL 대화창
	_draw_veil_dialogue()
	# 특징 셀 강조 칩 (패널 위)
	_feat_accents()
	# 특징 셀 우측 미니 아이콘
	_feat_icons()

func _draw_endings() -> void:
	for i in ENDINGS.size():
		var r: Rect2 = _ending_rect(i)
		draw_rect(r, Color(0.08, 0.10, 0.13, 0.92), true)
		draw_rect(r, COL_VEIL * Color(1, 1, 1, 0.40), false, 1.5)
		draw_line(r.position, r.position + Vector2(12, 0), COL_VEIL, 2.0)
		draw_line(r.position, r.position + Vector2(0, 12), COL_VEIL, 2.0)

func _draw_shots() -> void:
	for item in _shot_tex:
		var d: Dictionary = item
		var rect: Rect2 = d["rect"]
		var tex: Texture2D = d["tex"]
		draw_rect(rect, Color(0.06, 0.07, 0.09), true)
		if tex != null:
			draw_texture_rect(tex, rect, false)
		draw_rect(rect, COL_VEIL * Color(1, 1, 1, 0.55), false, 1.5)
		draw_line(rect.position, rect.position + Vector2(14, 0), COL_VEIL, 2.0)
		draw_line(rect.position, rect.position + Vector2(0, 14), COL_VEIL, 2.0)

func _draw_feat_panels() -> void:
	_panel(_feat_rect(0, 0), COL_VEIL)    # VEIL
	_panel(_feat_rect(1, 0), COL_COMBAT)  # 적
	_panel(_feat_rect(0, 1), COL_AMBER)   # 스킬
	_panel(_feat_rect(1, 1), COL_SURV)    # 맵

func _panel(rect: Rect2, accent: Color) -> void:
	draw_rect(rect, Color(0.085, 0.105, 0.14, 0.92), true)
	draw_rect(rect, accent * Color(1, 1, 1, 0.30), false, 1.0)

func _feat_accents() -> void:
	var sz: float = 22.0
	draw_rect(Rect2(FX_L, FY_1, sz, sz), COL_VEIL, true)
	draw_rect(Rect2(FX_R, FY_1, sz, sz), COL_COMBAT, true)
	# 스킬 셀 — 3계열 칩 (파랑 제외, 코랄/앰버/민트)
	draw_rect(Rect2(FX_L, FY_2, 6.0, sz), COL_COMBAT, true)
	draw_rect(Rect2(FX_L + 8.0, FY_2, 6.0, sz), COL_AMBER, true)
	draw_rect(Rect2(FX_L + 16.0, FY_2, 6.0, sz), COL_SURV, true)
	draw_rect(Rect2(FX_R, FY_2, sz, sz), COL_SURV, true)

# 각 특징 셀 우측 빈 공간에 상징 아이콘 — 셀 액센트색과 매칭.
func _feat_icons() -> void:
	var iy1: float = FY_1 - 18.0 + FBOX_H * 0.5
	var iy2: float = FY_2 - 18.0 + FBOX_H * 0.5
	var ixl: float = FX_L + 442.0
	var ixr: float = FX_R + 442.0
	_icon_veil_mark(Vector2(ixl, iy1), 24.0)  # VEIL — 위협 마킹 화살표
	_icon_enemy(Vector2(ixr, iy1), 24.0)      # 적 — 조준 레티클 + 표적
	_icon_skill(Vector2(ixl, iy2), 24.0)      # 스킬 — 3계열 원(삼각 배치)
	_icon_map(Vector2(ixr, iy2), 24.0)        # 맵 — 좌→우 분기 트리

func _icon_veil_mark(c: Vector2, r: float) -> void:
	# VEIL이 위협을 가리켜 마킹 — 시안 화살표가 표적(코랄)을 짚는다.
	var target: Vector2 = c + Vector2(r * 0.45, -r * 0.4)
	draw_circle(target, 3.0, COL_COMBAT)
	_ring(target, 6.5, 1.2, COL_VEIL * Color(1, 1, 1, 0.75))
	var tail: Vector2 = c + Vector2(-r * 0.72, r * 0.6)
	var head: Vector2 = target + Vector2(-9.0, 8.0)
	draw_line(tail, head, COL_VEIL * Color(1, 1, 1, 0.85), 2.0, true)
	var dir: Vector2 = (head - tail).normalized()
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	draw_line(head, head - dir * 7.0 + perp * 4.0, COL_VEIL, 2.0, true)
	draw_line(head, head - dir * 7.0 - perp * 4.0, COL_VEIL, 2.0, true)

func _icon_enemy(c: Vector2, r: float) -> void:
	var col: Color = COL_COMBAT
	_ring(c, r, 1.5, col * Color(1, 1, 1, 0.7))
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		draw_line(c + d * (r - 4.0), c + d * (r + 4.0), col * Color(1, 1, 1, 0.6), 1.5, true)
	var s: float = r * 0.42
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0)]), col)

func _icon_skill(c: Vector2, r: float) -> void:
	# 3계열을 원으로 감싸 삼각형 꼭짓점에 배치 (전투/스킬/생존).
	var cols: Array = [COL_COMBAT, COL_AMBER, COL_SURV]
	var pts: Array = [
		c + Vector2(0, -r * 0.66),
		c + Vector2(-r * 0.74, r * 0.48),
		c + Vector2(r * 0.74, r * 0.48),
	]
	for i in 3:
		var pc: Color = cols[i]
		draw_circle(pts[i], r * 0.36, pc * Color(1, 1, 1, 0.45))
		_ring(pts[i], r * 0.36, 1.3, pc * Color(1, 1, 1, 0.9))

func _icon_map(c: Vector2, r: float) -> void:
	# 좌→우 분기 트리 — 루트 1개에서 3갈래로 뻗어 "다양한 경로".
	var col: Color = COL_SURV
	var root: Vector2 = c + Vector2(-r, 0)
	var fork: Vector2 = c + Vector2(-r * 0.15, 0)
	var tips: Array = [c + Vector2(r, -r * 0.72), c + Vector2(r, 0), c + Vector2(r, r * 0.72)]
	draw_line(root, fork, col * Color(1, 1, 1, 0.6), 1.5, true)
	for t in tips:
		draw_line(fork, t, col * Color(1, 1, 1, 0.6), 1.5, true)
		draw_circle(t, 3.0, col)
	draw_circle(root, 3.5, col)
	draw_circle(fork, 3.0, col * Color(1, 1, 1, 0.85))

func _draw_veil_dialogue() -> void:
	var rect: Rect2 = Rect2(M, DLG_Y, W - 2.0 * M, DLG_H)
	draw_rect(rect, Color(0.07, 0.12, 0.155, 0.94), true)
	draw_rect(rect, COL_VEIL * Color(1, 1, 1, 0.45), false, 1.5)
	# 좌상단 코너 틱 (대화창 느낌)
	draw_line(rect.position, rect.position + Vector2(16, 0), COL_VEIL, 2.0)
	draw_line(rect.position, rect.position + Vector2(0, 16), COL_VEIL, 2.0)
	# 좌측 VEIL 눈 아이콘
	_draw_eye(Vector2(M + 56.0, DLG_Y + DLG_H * 0.5), 32.0)

# ── VEIL 눈 (BriefingVisual.gd _draw 모티프, 정적 포즈 + 글로우 halo) ──
func _draw_eye(c: Vector2, r: float) -> void:
	var col: Color = COL_VEIL
	# 외곽 글로우 halo — 이목 강화("감시 카메라/레이더" 분위기)
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

# ── 텍스트 (Label 자식) ──
func _build_text() -> void:
	# 타이틀 — outline 강화(faux-bold)로 엔진 기본 폰트의 가는 획을 보강.
	_label("EYES ON YOU", Vector2(M, 400.0), W - 2.0 * M, 128, COL_WHITE, HORIZONTAL_ALIGNMENT_CENTER, false, 9)
	_label("단 하나의 임무, 네 가지 결말", Vector2(M, 576.0), W - 2.0 * M, 36, COL_VEIL, HORIZONTAL_ALIGNMENT_CENTER, false, 5)
	_label("현장 요원인 당신에게, 상황실 AI 'VEIL'이 보이지 않는 위협을 미리 짚어준다.\n그 조언을 따를지 무시할지 — 당신의 선택이 결말과 VEIL의 정체를 가른다.",
		Vector2((W - 1000.0) * 0.5, 638.0), 1000.0, 23, COL_GRAY, HORIZONTAL_ALIGNMENT_CENTER, true)
	# ── 엔딩 행 ──
	_label("어떤 끝에 닿을까", Vector2(M, 730.0), W - 2.0 * M, 16,
		COL_VEIL * Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_LEFT, false)
	_label("신뢰 × 전투", Vector2(M, 731.0), W - 2.0 * M, 15,
		COL_DIM, HORIZONTAL_ALIGNMENT_RIGHT, false)
	_ending_labels()
	# ── 스크린샷 섹션 ──
	_label("직접 플레이 화면 · 12개 루트", Vector2(M, 872.0), W - 2.0 * M, 16,
		COL_VEIL * Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_LEFT, false)
	_shot_captions(SHOT_Y + SHOT_H + 8.0)
	# ── 특징 2×2 ──
	_label("주요 특징", Vector2(M, 1114.0), W - 2.0 * M, 16,
		COL_VEIL * Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_LEFT, false)
	_feat_cell(FX_L, FY_1, 38.0, "VEIL, 당신을 보는 AI",
		"위협을 미리 짚어주는 상황실 AI 파트너\n조언을 따른 정도에 갈리는 결말")
	_feat_cell(FX_R, FY_1, 38.0, "5종의 적, 제각각의 약점",
		"정찰병·저격수·드론·자폭병·방패병\n약점을 노려 스킬로 받아치는 전투")
	_feat_cell(FX_L, FY_2, 56.0, "8개 스킬 라인, 나만의 빌드",
		"전투·이동·생존 3계열\n레벨업마다 고르는 한 가지")
	_feat_cell(FX_R, FY_2, 38.0, "12개 맵, 매번 다른 길",
		"스테이지마다 추첨되는 분기 루트\n위험을 감수할수록 커지는 보상")
	# ── VEIL 대화창 텍스트 ──
	_label("VEIL", Vector2(M + 126.0, DLG_Y + 20.0), 200.0, 17, COL_VEIL, HORIZONTAL_ALIGNMENT_LEFT, false)
	_label("“믿을수록 더 도와드릴 수 있어요.”",
		Vector2(M + 126.0, DLG_Y + 46.0), W - 2.0 * M - 156.0, 27, COL_WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
	# ── 정보칩 + 푸터 ──
	_label("횡스크롤 로그라이트     ·     8–15분     ·     4종 결말",
		Vector2(M, 1548.0), W - 2.0 * M, 20, COL_DIM, HORIZONTAL_ALIGNMENT_CENTER, false)
	_label("▶  soomin007.github.io/EyesOnYou", Vector2(M, 1584.0), W - 2.0 * M, 23, COL_VEIL, HORIZONTAL_ALIGNMENT_CENTER, false)
	_label("자유전공학부 김수민", Vector2(M, 1624.0), W - 2.0 * M, 18,
		COL_VEIL * Color(1, 1, 1, 0.92), HORIZONTAL_ALIGNMENT_CENTER, false)
	_label("Windows PC · 키보드 / 게임패드 · Godot 4.6",
		Vector2(M, 1656.0), W - 2.0 * M, 15, COL_DIM, HORIZONTAL_ALIGNMENT_CENTER, false)

func _ending_labels() -> void:
	for i in ENDINGS.size():
		var pair: Array = ENDINGS[i]
		var r: Rect2 = _ending_rect(i)
		_label(str(pair[0]), Vector2(r.position.x, r.position.y + 6.0), r.size.x, 38,
			COL_VEIL, HORIZONTAL_ALIGNMENT_CENTER, false)
		_label(str(pair[1]), Vector2(r.position.x, r.position.y + 58.0), r.size.x, 14,
			COL_GRAY, HORIZONTAL_ALIGNMENT_CENTER, false)

func _shot_captions(cy: float) -> void:
	var i: int = 0
	for entry in SHOTS:
		var pair: Array = entry
		var rect: Rect2 = (_shot_tex[i] as Dictionary)["rect"]
		_label(str(pair[1]), Vector2(rect.position.x, cy), SHOT_W, 14, COL_DIM, HORIZONTAL_ALIGNMENT_CENTER, false)
		i += 1

func _feat_cell(x: float, y: float, head_off: float, head: String, desc: String) -> void:
	var tw: float = FCW - 96.0   # 우측 아이콘 공간 확보
	_label(head, Vector2(x + head_off, y - 2.0), tw - head_off, 23, COL_WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
	_label(desc, Vector2(x, y + 38.0), tw, 17, COL_GRAY, HORIZONTAL_ALIGNMENT_LEFT, true)

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
