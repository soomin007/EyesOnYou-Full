class_name ArcturusDocumentOverlay
extends Node

# 이스터에그 ARCTURUS 아카이브 — 풀스크린 문서 연출.
# 종이 한 장에 위에서부터 줄들이 타이핑되며 나타나고, 카메라(종이)가 자동 스크롤.
# 시간 정지 + 스페이스/클릭으로 현재 줄 즉시 완성 + 다음 줄로.
#
# 사용:
#   var doc = ArcturusDocumentOverlay.new()
#   parent.add_child(doc)
#   doc.finished.connect(_on_done)
#   doc.show_doc(lines)   # lines: Array of {text: String, kind: "title"/"body"/"speaker", delay: float}

signal finished

# 가독 리워크(2026-08-23 사용자 "글씨는 작고 여백만 잔뜩 · 읽기 싫게 생겼다") — 종이 폭·폰트
# 확대 + 핵심 줄 형광펜 강조("hl": true — 대충 봐도 스토리 흐름이 잡히게).
const TYPE_INTERVAL: float = 0.035
const PAPER_WIDTH: float = 880.0
const MARGIN_TOP: float = 64.0
const MARGIN_SIDE: float = 44.0
const LINE_HEIGHT_BODY: float = 46.0
const LINE_HEIGHT_TITLE: float = 62.0
const LINE_HEIGHT_BLANK: float = 20.0
# 디자인 기준 화면 크기 — show_doc 진입 시 실제 화면(visible_rect)으로 갱신(적응형).
# const가 아니라 var: 런타임에 현재 해상도/화면비로 덮어쓴다(아래 모든 사용처에 반영).
var VIEWPORT_W: float = 1280.0
var VIEWPORT_H: float = 720.0
const SCROLL_LERP: float = 0.085  # 카메라 부드럽게 따라옴

var layer: CanvasLayer
var bg: ColorRect
var paper: Control
var paper_visual: ColorRect
var labels: Array = []   # Label 배열, 입력 lines와 1:1
var lines_data: Array = []
var current_line: int = 0
var revealed: int = 0
var typing: bool = false
var t: float = 0.0
var pause_after_line: float = 0.0
var done: bool = false
var paper_target_y: float = 0.0
# 다 나온 뒤 사용자 조작 단계 — 위/아래로 스크롤 + 확인 키로 닫기.
var reading_done: bool = false
var read_lockout_t: float = 0.0
const READ_LOCKOUT: float = 0.7
const SCROLL_STEP: float = 200.0
var close_hint_label: Label = null
# 페이드인 중 _process가 자동 진행해 line 1/2가 미리 visible되던 버그(사용자:
# "[A] 인사팀 온보까지만 보이다가 지워졌다 다시 써짐") 차단. _start_typing이
# 콜백으로 호출될 때 비로소 typing 시작.
var started: bool = false
# 진입 직전(이스터에그 hold 완료 직후) jump 키 잔여 입력이 _input으로 들어와
# typing이 자동 진행되어 [A] 인사팀 온보딩 본문까지 시작부터 보이는 버그 차단.
# _start_typing 콜백 후에도 짧게 더 무시.
const ENTER_LOCKOUT: float = 0.4
var enter_lockout_t: float = 0.0
# 문서 스타일 — "paper"(크림 종이, 기본) / "terminal"(어두운 서버 콘솔 · 2차 피드백:
# 서버 로그가 종이 위 파란 형광으로는 로그처럼 안 읽힘 → 터미널 화면을 옮긴 느낌으로).
# show_doc 호출 전에 세팅한다.
var style: String = "paper"
var _kw_color: String = "#0a4a73"   # [[키워드]] 강조색 — 스타일별로 show_doc에서 결정

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func show_doc(input_lines: Array) -> void:
	SfxPlayer.play("arcturus_enter")
	lines_data = input_lines
	# 적응형 — 실제 화면 크기로 기준 갱신 (종이 중앙·하단 안내·스크롤 한계가 화면비 무관).
	var vp: Vector2 = get_viewport().get_visible_rect().size
	VIEWPORT_W = vp.x
	VIEWPORT_H = vp.y
	layer = CanvasLayer.new()
	layer.layer = 25
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	# 풀스크린 어두운 배경
	bg = ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04, 0.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)
	# 종이 컨테이너 (화면 가운데 가로 정렬)
	paper = Control.new()
	paper.position = Vector2((VIEWPORT_W - PAPER_WIDTH) * 0.5, MARGIN_TOP)
	paper.size = Vector2(PAPER_WIDTH, _calc_paper_height())
	paper.modulate.a = 0.0
	layer.add_child(paper)
	# paper_target_y 초기값을 시작 position과 동기화 — 안 그러면 0(기본값)으로
	# lerp되어 페이드인 0.7s 동안 paper가 화면 위로 빠져나가서 제목이 안 보이고
	# 본문(A 온보딩 등)이 먼저 등장하는 것처럼 보임 (사용자 보고).
	paper_target_y = MARGIN_TOP
	# 문서별 양식(3차 피드백 "각 양식에 맞는 그래픽") — paper: 크림 종이+레터헤드+스탬프 /
	# terminal: 서버 콘솔 / drive: 회수 드라이브 복호화 뷰어(어두운 보라).
	var is_term: bool = style == "terminal"
	var is_drive: bool = style == "drive"
	if is_term:
		_kw_color = "#ffc857"
	elif is_drive:
		_kw_color = "#c9a2ff"
	else:
		_kw_color = "#0a4a73"
	# 콘솔 계열 양식은 코딩 폰트(D2Coding, OFL) — 사용자 제안 2026-08-23. 종이는 프리텐다드 유지.
	var mono: FontFile = null
	if is_term or is_drive:
		mono = load("res://assets/fonts/D2Coding.ttf")
	paper_visual = ColorRect.new()
	if is_term:
		paper_visual.color = Color(0.043, 0.055, 0.075, 0.97)
	elif is_drive:
		paper_visual.color = Color(0.055, 0.042, 0.085, 0.97)
	else:
		paper_visual.color = Color(0.92, 0.90, 0.84, 0.96)
	# 종이 양식은 레터헤드·스탬프 확대(4차 피드백 "더 커도 될 것 같다")로 머리 여백을 더 쓴다.
	var head_room: float = 40.0 if (is_term or is_drive) else 68.0
	paper_visual.position = Vector2(-MARGIN_SIDE, -head_room)
	paper_visual.size = paper.size + Vector2(MARGIN_SIDE * 2.0, head_room + 40.0)
	paper.add_child(paper_visual)
	# 종이 옆 가는 그림자 라인 (저격 같은 디테일)
	var shadow := ColorRect.new()
	shadow.color = Color(0.0, 0.0, 0.0, 0.18)
	shadow.position = Vector2(-MARGIN_SIDE - 6.0, -head_room + 6.0)
	shadow.size = paper_visual.size
	shadow.z_index = -1
	paper.add_child(shadow)
	if is_term or is_drive:
		# 콘솔/뷰어 타이틀 바 — 창 점 3개 + 세션 경로. 화면 밖 스크롤을 따라가지 않게 paper가
		# 아니라 layer(화면 고정)에 붙인다. 텍스트는 기술 표기(영문 경로)라 대사 검수 대상 아님.
		var bar := ColorRect.new()
		bar.color = Color(0.075, 0.095, 0.125, 1.0) if is_term else Color(0.105, 0.075, 0.165, 1.0)
		bar.position = Vector2((VIEWPORT_W - PAPER_WIDTH) * 0.5 - MARGIN_SIDE, 0.0)
		bar.size = Vector2(PAPER_WIDTH + MARGIN_SIDE * 2.0, 30.0)
		layer.add_child(bar)
		var dots := Label.new()
		dots.text = "● ● ●"
		dots.add_theme_font_size_override("font_size", 9)
		dots.add_theme_color_override("font_color", Color(0.45, 0.55, 0.60))
		dots.position = Vector2(14.0, 7.0)
		bar.add_child(dots)
		var path_l := Label.new()
		path_l.text = "svr-03 : /var/log/veil.d/recovered.log" if is_term else "drive-A7 : decrypt · read-only"
		if mono != null:
			path_l.add_theme_font_override("font", mono)
		path_l.add_theme_font_size_override("font_size", 13)
		path_l.add_theme_color_override("font_color", Color(0.48, 0.75, 0.58) if is_term else Color(0.74, 0.58, 0.96))
		path_l.position = Vector2(0.0, 4.0)
		path_l.size = Vector2(bar.size.x, 22.0)
		path_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bar.add_child(path_l)
		# 은은한 스캔라인 — 4px 간격 수평선(수직 줄무늬 금지 규칙과 별개, CRT 문법은 수평).
		var scan := ColorRect.new()
		scan.color = Color(1, 1, 1, 1)
		scan.position = paper_visual.position
		scan.size = paper_visual.size
		scan.material = _make_scanline_material()
		paper.add_child(scan)
		# 콘솔 창 프레임 — 가장자리 1px 라인(4차 피드백 "더 꾸밀 요소"). 스크롤을 따라간다.
		var frame := Panel.new()
		var fr_sb := StyleBoxFlat.new()
		fr_sb.bg_color = Color(0, 0, 0, 0)
		fr_sb.border_color = Color(0.30, 0.55, 0.42, 0.55) if is_term else Color(0.48, 0.36, 0.72, 0.55)
		fr_sb.set_border_width_all(1)
		frame.add_theme_stylebox_override("panel", fr_sb)
		frame.position = paper_visual.position
		frame.size = paper_visual.size
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		paper.add_child(frame)
		# 하단 상태 바 — 세션 정보 + 깜빡이는 블록 커서(터미널 문법). 타이틀 바처럼 화면 고정.
		# 텍스트는 기술 표기(영문)라 대사 검수 대상 아님.
		var foot := ColorRect.new()
		foot.color = bar.color
		foot.position = Vector2(bar.position.x, VIEWPORT_H - 26.0)
		foot.size = Vector2(bar.size.x, 26.0)
		layer.add_child(foot)
		var foot_l := Label.new()
		if is_term:
			foot_l.text = "svr-03 · READ-ONLY · %d LINES RECOVERED" % lines_data.size()
		else:
			foot_l.text = "drive-A7 · DECRYPT OK · %d ENTRIES" % lines_data.size()
		if mono != null:
			foot_l.add_theme_font_override("font", mono)
		foot_l.add_theme_font_size_override("font_size", 12)
		foot_l.add_theme_color_override("font_color", Color(0.42, 0.62, 0.50) if is_term else Color(0.62, 0.50, 0.82))
		foot_l.position = Vector2(14.0, 4.0)
		foot_l.size = Vector2(foot.size.x - 48.0, 18.0)
		foot.add_child(foot_l)
		var cur := Label.new()
		cur.text = "▮"
		if mono != null:
			cur.add_theme_font_override("font", mono)
		cur.add_theme_font_size_override("font_size", 13)
		cur.add_theme_color_override("font_color", Color(0.45, 0.85, 0.58) if is_term else Color(0.75, 0.55, 1.0))
		cur.position = Vector2(foot.size.x - 26.0, 3.0)
		foot.add_child(cur)
		var ctw := cur.create_tween()
		ctw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		ctw.set_loops()
		ctw.tween_property(cur, "modulate:a", 0.12, 0.5)
		ctw.tween_property(cur, "modulate:a", 1.0, 0.5)
	else:
		# 종이 양식 — 레터헤드(기관명 + 이중 괘선) + 붉은 분류 스탬프. 인사 아카이브 컨셉.
		# 4차 피드백 "레터헤드와 스탬프가 좀 더 커도 될 것 같다" — 19px/20px로 확대.
		var lh := Label.new()
		lh.text = "ARCTURUS · PERSONNEL ARCHIVE"
		lh.add_theme_font_size_override("font_size", 19)
		lh.add_theme_color_override("font_color", Color(0.33, 0.36, 0.48, 0.9))
		lh.position = Vector2(0.0, -60.0)
		paper.add_child(lh)
		var rule := ColorRect.new()
		rule.color = Color(0.30, 0.33, 0.45, 0.55)
		rule.position = Vector2(0.0, -28.0)
		rule.size = Vector2(PAPER_WIDTH, 2.0)
		paper.add_child(rule)
		var rule2 := ColorRect.new()
		rule2.color = Color(0.30, 0.33, 0.45, 0.35)
		rule2.position = Vector2(0.0, -24.0)
		rule2.size = Vector2(PAPER_WIDTH, 1.0)
		paper.add_child(rule2)
		var stamp := PanelContainer.new()
		var st_sb := StyleBoxFlat.new()
		st_sb.bg_color = Color(0, 0, 0, 0)
		st_sb.border_color = Color(0.72, 0.18, 0.16, 0.70)
		st_sb.set_border_width_all(3)
		st_sb.content_margin_left = 14.0
		st_sb.content_margin_right = 14.0
		st_sb.content_margin_top = 3.0
		st_sb.content_margin_bottom = 3.0
		stamp.add_theme_stylebox_override("panel", st_sb)
		stamp.position = Vector2(PAPER_WIDTH - 225.0, -64.0)
		stamp.rotation = -0.045
		var st_l := Label.new()
		st_l.text = "RESTRICTED"
		st_l.add_theme_font_size_override("font_size", 20)
		st_l.add_theme_color_override("font_color", Color(0.72, 0.18, 0.16, 0.78))
		stamp.add_child(st_l)
		paper.add_child(stamp)
	# 줄들 미리 배치 (alpha=0)
	var y: float = 0.0
	for entry in lines_data:
		var d: Dictionary = entry
		var kind: String = str(d.get("kind", "body"))
		# RichTextLabel — [[키워드]]만 진청으로 물들인다(줄 전체 형광펜 밴드는 "책 전체에
		# 형광펜" 반려로 폐지, 2026-08-23). 타이핑은 visible_characters로(태그 substr 깨짐 방지).
		var lbl := RichTextLabel.new()
		lbl.bbcode_enabled = true
		lbl.scroll_active = false
		if mono != null:
			lbl.add_theme_font_override("normal_font", mono)
		lbl.position = Vector2(0.0, y)
		lbl.size = Vector2(PAPER_WIDTH, _line_height_for(kind))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.modulate.a = 0.0
		match kind:
			"title":
				lbl.add_theme_font_size_override("normal_font_size", 30)
				var tc := Color(0.18, 0.20, 0.28)
				if is_term:
					tc = Color(0.45, 0.85, 0.58)
				elif is_drive:
					tc = Color(0.75, 0.55, 1.0)
				lbl.add_theme_color_override("default_color", tc)
			"speaker":
				lbl.add_theme_font_size_override("normal_font_size", 18)
				var sc := Color(0.45, 0.45, 0.55)
				if is_term:
					sc = Color(0.42, 0.58, 0.50)
				elif is_drive:
					sc = Color(0.56, 0.48, 0.70)
				lbl.add_theme_color_override("default_color", sc)
			"blank":
				lbl.add_theme_font_size_override("normal_font_size", 16)
			_:
				lbl.add_theme_font_size_override("normal_font_size", 23)
				var bc := Color(0.10, 0.12, 0.18)
				if is_term:
					bc = Color(0.72, 0.80, 0.78)
				elif is_drive:
					bc = Color(0.80, 0.75, 0.90)
				lbl.add_theme_color_override("default_color", bc)
		lbl.text = _to_bbcode(str(d.get("text", "")))
		lbl.visible_characters = 0
		paper.add_child(lbl)
		labels.append(lbl)
		y += _line_height_for(kind)
	# 페이드 인 → 타이핑 시작
	get_tree().paused = true
	var tw_bg := bg.create_tween()
	tw_bg.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw_bg.tween_property(bg, "color:a", 0.92, 0.6)
	var tw_paper := paper.create_tween()
	tw_paper.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw_paper.tween_property(paper, "modulate:a", 1.0, 0.7)
	tw_paper.tween_callback(_start_typing)

# [[키워드]] -> 진청 색 강조 bbcode. 원문 대괄호는 [lb]로 이스케이프해 그대로 보이게.
func _to_bbcode(raw: String) -> String:
	var out: String = raw.replace("[[", "").replace("]]", "")
	out = out.replace("[", "[lb]")
	out = out.replace("", "[color=%s]" % _kw_color).replace("", "[/color]")
	return out

func _calc_paper_height() -> float:
	var h: float = 0.0
	for entry in lines_data:
		var d: Dictionary = entry
		h += _line_height_for(str(d.get("kind", "body")))
	return max(h, VIEWPORT_H - MARGIN_TOP * 2.0)

func _line_height_for(kind: String) -> float:
	match kind:
		"title":
			return LINE_HEIGHT_TITLE
		"blank":
			return LINE_HEIGHT_BLANK
	return LINE_HEIGHT_BODY

func _start_typing() -> void:
	started = true
	enter_lockout_t = ENTER_LOCKOUT
	current_line = 0
	revealed = 0
	t = 0.0
	if labels.size() > 0:
		typing = true
		labels[0].modulate.a = 1.0

func _process(delta: float) -> void:
	if done:
		return
	# 종이 부드럽게 스크롤 (현재 줄을 화면 중앙 ~40%에 위치)
	paper.position.y = lerp(paper.position.y, paper_target_y, SCROLL_LERP)
	# 페이드인 중엔 typing 진행 X — _start_typing 콜백이 started=true로 바꿔야 시작.
	if not started:
		return
	if enter_lockout_t > 0.0:
		enter_lockout_t -= delta
	# 다 읽고 나면 자동 진행 멈추고 사용자 스크롤 + 확인 키 대기.
	if reading_done:
		if read_lockout_t > 0.0:
			read_lockout_t -= delta
		_handle_user_scroll(delta)
		return
	if current_line >= lines_data.size():
		return
	if typing:
		t += delta
		if t >= TYPE_INTERVAL:
			t = 0.0
			revealed += 1
			var line: Dictionary = lines_data[current_line]
			var label: RichTextLabel = labels[current_line]
			var total: int = label.get_total_character_count()
			if revealed >= total:
				revealed = total
				label.visible_characters = -1
				typing = false
				pause_after_line = float(line.get("delay", 0.4))
			else:
				label.visible_characters = revealed
				SfxPlayer.play("terminal_typewrite")
		_update_scroll_target()
		return
	# 줄 사이 침묵 → 다음 줄로
	pause_after_line -= delta
	if pause_after_line <= 0.0:
		current_line += 1
		if current_line >= lines_data.size():
			_enter_reading_done()
		else:
			revealed = 0
			t = 0.0
			typing = true
			labels[current_line].modulate.a = 1.0
			# blank 줄은 텍스트 없어 즉시 통과
			var ln: Dictionary = lines_data[current_line]
			if str(ln.get("kind", "body")) == "blank":
				typing = false
				pause_after_line = float(ln.get("delay", 0.2))
			_update_scroll_target()

func _update_scroll_target() -> void:
	# 현재 줄의 종이 내부 y 좌표
	if current_line >= labels.size():
		return
	var lbl_y: float = labels[current_line].position.y
	# paper의 절대 좌표가 (VIEWPORT_H * 0.42 - lbl_y)일 때 그 줄이 화면 약 42% 위치.
	var target: float = VIEWPORT_H * 0.42 - lbl_y
	# 종이가 너무 위로 올라가지 않게 clamp (최대 상단 = MARGIN_TOP)
	if target > MARGIN_TOP:
		target = MARGIN_TOP
	paper_target_y = target

func _enter_reading_done() -> void:
	# 자동 진행 종료. 사용자 스크롤 + 확인 키 대기.
	if reading_done:
		return
	reading_done = true
	read_lockout_t = READ_LOCKOUT
	# 화면 하단 닫기 안내.
	close_hint_label = Label.new()
	close_hint_label.text = "[ ↑↓ · W/S · 휠 스크롤   Space·Enter로 닫기 ]"
	close_hint_label.add_theme_font_size_override("font_size", 14)
	close_hint_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.78))
	close_hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	close_hint_label.add_theme_constant_override("outline_size", 4)
	close_hint_label.position = Vector2(0, VIEWPORT_H - 40.0)
	close_hint_label.size = Vector2(VIEWPORT_W, 28.0)
	close_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_hint_label.modulate.a = 0.0
	layer.add_child(close_hint_label)
	var tw := close_hint_label.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_interval(READ_LOCKOUT)
	tw.tween_property(close_hint_label, "modulate:a", 1.0, 0.4)

func _handle_user_scroll(_delta: float) -> void:
	# 위/아래 hold로 paper_target_y 조정 — 사용자가 다시 읽을 수 있게.
	# W/S는 jump 등에 묶여 ui_up/down에 안 붙을 수 있어 물리 키로 직접 체크(사용자: WS로도 스크롤).
	if Input.is_action_pressed("ui_up") or Input.is_action_pressed("move_left") or Input.is_key_pressed(KEY_W):
		_scroll_paper(12.0)
	elif Input.is_action_pressed("ui_down") or Input.is_action_pressed("move_right") or Input.is_key_pressed(KEY_S):
		_scroll_paper(-12.0)

# 종이를 amount만큼 스크롤하고 윗단/아랫단 클램프. 키 hold·마우스 휠 공용.
func _scroll_paper(amount: float) -> void:
	paper_target_y += amount
	var min_y: float = -(paper.size.y - VIEWPORT_H + MARGIN_TOP * 2.0)
	if min_y > MARGIN_TOP:
		min_y = MARGIN_TOP
	paper_target_y = clamp(paper_target_y, min_y, MARGIN_TOP)

func _input(event: InputEvent) -> void:
	if done:
		return
	# 페이드인 중 + 진입 직후 마진 — 이전 화면 점프 키 잔여 입력 차단.
	if not started or enter_lockout_t > 0.0:
		return
	# 다 읽힌 상태 — 위/아래는 _process polling, 확인 키는 lockout 후 닫기.
	if reading_done:
		if read_lockout_t > 0.0:
			return
		# 마우스 휠 — 종이 스크롤 (휠 업=위로 거슬러 보기). 사용자: 휠로도 스크롤.
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_scroll_paper(48.0)
				get_viewport().set_input_as_handled()
				return
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_scroll_paper(-48.0)
				get_viewport().set_input_as_handled()
				return
		# 닫기 — 확인 키(Space/Enter)·스킵·공격·좌클릭·화면 탭. jump(W)는 스크롤에 쓰므로 닫기에서 뺀다.
		var close_pressed: bool = false
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_skip") or event.is_action_pressed("attack") or OrientationGuard.is_tap(event):
			close_pressed = true
		# 터치 기기에선 화면 탭이 좌클릭으로도 합성(emulate_mouse_from_touch)돼 is_tap과 중복 → 데스크톱만.
		elif not OrientationGuard.is_touch_device() and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close_pressed = true
		if close_pressed:
			get_viewport().set_input_as_handled()
			_start_finalize()
		return
	var pressed: bool = false
	if event.is_action_pressed("jump") or event.is_action_pressed("ui_skip") or event.is_action_pressed("attack") or OrientationGuard.is_tap(event):
		pressed = true
	# 터치 기기: 화면 탭이 좌클릭으로도 합성돼 is_tap과 중복(한 탭에 2줄 스킵) → 데스크톱만 좌클릭 인정.
	elif not OrientationGuard.is_touch_device() and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = true
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	if current_line >= lines_data.size():
		_enter_reading_done()
		return
	if typing:
		# 현재 줄 즉시 완성
		var rl: RichTextLabel = labels[current_line]
		rl.visible_characters = -1
		revealed = rl.get_total_character_count()
		typing = false
		pause_after_line = 0.0
	else:
		# 다음 줄로 스킵
		current_line += 1
		if current_line >= lines_data.size():
			_enter_reading_done()
			return
		revealed = 0
		t = 0.0
		typing = true
		labels[current_line].modulate.a = 1.0
		var ln: Dictionary = lines_data[current_line]
		if str(ln.get("kind", "body")) == "blank":
			typing = false
			pause_after_line = 0.0
		_update_scroll_target()

func _start_finalize() -> void:
	if done:
		return
	done = true
	var tw := bg.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_interval(1.4)
	tw.tween_property(bg, "color:a", 0.0, 0.9)
	var tw_p := paper.create_tween()
	tw_p.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw_p.tween_interval(1.4)
	tw_p.tween_property(paper, "modulate:a", 0.0, 0.9)
	tw_p.tween_callback(_emit_done)

func _emit_done() -> void:
	get_tree().paused = false
	emit_signal("finished")
	if layer != null and is_instance_valid(layer):
		layer.queue_free()

# 안전판: _emit_done이 어떤 이유로든 호출 안 된 채 self가 tree에서 빠지면 paused 해제.
# (외부 free / scene 전환 / 예외 등)
func _exit_tree() -> void:
	var tree := get_tree()
	if tree != null:
		tree.paused = false

# 터미널 스캔라인 — 4px 주기의 은은한 수평선(CRT 문법). 콘솔 창 위에만 깔린다.
func _make_scanline_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;
void fragment() {
	float ln = mod(FRAGCOORD.y, 4.0) < 1.0 ? 0.09 : 0.0;
	COLOR = vec4(0.0, 0.0, 0.0, ln);
}
"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	return mat
