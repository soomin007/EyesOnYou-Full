class_name ArcturusDocumentOverlay
extends Node

# 이스터에그 ARCTURUS 아카이브 · 풀스크린 문서 연출.
# 종이 한 장에 위에서부터 줄들이 타이핑되며 나타나고, 카메라(종이)가 자동 스크롤.
# 시간 정지 + 스페이스/클릭으로 현재 줄 즉시 완성 + 다음 줄로.
#
# 사용:
#   var doc = ArcturusDocumentOverlay.new()
#   parent.add_child(doc)
#   doc.finished.connect(_on_done)
#   doc.show_doc(lines)   # lines: Array of {text: String, kind: String, delay: float, ...}
#
# 행 종류(kind) · 문서 서식 리뉴얼(2026-08-30 사용자 "배경만 다르고 글은 전부 왼쪽 정렬 줄글"):
#   공통   title(제목) · blank(간격, h) · rule(괘선) · body(줄글) · speaker(옛 발화자 라벨)
#   서식   section(하위 문서 머리 · tag/badge/text) · kv(라벨: 값 · label/text · right_label/right_text ·
#          gap) · form(표 행 · label/text · last) · para(문단) · num(번호 항목 · n) · note(비고 상자 ·
#          label) · sign(서명 · sub) · redacted(검열 바) · sheet(장 경계) · cut(발췌 절단부 · 점선)
#   콘솔   prompt(프롬프트 줄) · log(로그 행 · ts/lvl) · corrupt(덮어쓰인 구간 · rows) · gap(건너뜀 표기)
#   뷰어   bar(복호화 게이지 · % 카운트업) · hex(헥스 덤프 줄)
#   행 옵션(15차 리뉴얼 · 2026-08-31): fast=타이핑 없이 통째 등장(고속 덤프 · 연속되면 좌라락 스크롤) ·
#   live=드러나는 순간 ts를 실제 현재 시각으로(지금 쓰이고 있는 줄) · slow=글자당 t_int로 느리게 +
#   틱 SFX + 완성 스팅·화면 틴트(빌드 서명 VEIL 전용) · t_int=행별 타이핑 간격 오버라이드.
#   타이핑 대상은 행마다 RichTextLabel 하나(labels[i]) · 행 컨테이너(rows[i])가 라벨 열·괘선·상자를 함께
#   담는다. 행 높이는 실측(get_content_height)으로 쌓는다. [[키워드]]=강조색, [REDACTED]=검열 바.

signal finished

# 가독 리워크(2026-08-23 사용자 "글씨는 작고 여백만 잔뜩 · 읽기 싫게 생겼다") · 종이 폭·폰트
# 확대 + 핵심 줄 형광펜 강조("hl": true · 대충 봐도 스토리 흐름이 잡히게).
const TYPE_INTERVAL: float = 0.035
const PAPER_WIDTH: float = 880.0
const MARGIN_TOP: float = 64.0
const MARGIN_SIDE: float = 44.0
# 디자인 기준 화면 크기 · show_doc 진입 시 실제 화면(visible_rect)으로 갱신(적응형).
# const가 아니라 var: 런타임에 현재 해상도/화면비로 덮어쓴다(아래 모든 사용처에 반영).
var VIEWPORT_W: float = 1280.0
var VIEWPORT_H: float = 720.0
const SCROLL_LERP: float = 0.085  # 카메라 부드럽게 따라옴

var layer: CanvasLayer
var bg: ColorRect
var paper: Control
var paper_visual: ColorRect
var labels: Array = []   # RichTextLabel(타이핑 대상) 배열, lines_data와 1:1
var rows: Array = []     # 행 컨테이너(Control) 배열, lines_data와 1:1 · 라벨 열·괘선·상자 포함
var _scan: ColorRect = null   # 콘솔 스캔라인 · 행 실측 후 종이 크기에 맞춘다
var _frame: Panel = null      # 콘솔 창 프레임 · 위와 같음
var _pal: Dictionary = {}     # 양식별 팔레트(_setup_palette)
var _font_main: Font = null
var _font_bold: Font = null
var _head_room: float = 68.0
var lines_data: Array = []
var current_line: int = 0
var revealed: int = 0
var typing: bool = false
var t: float = 0.0
var pause_after_line: float = 0.0
var done: bool = false
var paper_target_y: float = 0.0
# 고속 덤프 연속 카운트 · fast 행이 이어지는 동안 스크롤 추적을 가속하고 SFX를 성기게 낸다.
var _fast_streak: int = 0
# 다 나온 뒤 사용자 조작 단계 · 위/아래로 스크롤 + 확인 키로 닫기.
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
# 문서 스타일 · "paper"(크림 종이, 기본) / "terminal"(어두운 서버 콘솔 · 2차 피드백:
# 서버 로그가 종이 위 파란 형광으로는 로그처럼 안 읽힘 → 터미널 화면을 옮긴 느낌으로).
# show_doc 호출 전에 세팅한다.
var style: String = "paper"
# 캔버스 레이어 번호 · 기본 25(자막 20 위 · 클리어 페이드 38 아래). 설정 디버그 탭에서 열 때는 일시정지
# 메뉴(30) 위에 와야 하므로 호출자가 show_doc 전에 올린다.
var layer_index: int = 25
var _kw_color: String = "#0a4a73"   # [[키워드]] 강조색 · 스타일별로 show_doc에서 결정
# 양식별 등장 연출(5차 피드백 "처음부터 펼쳐져 있지 않게") · 종이는 봉인 펼침, 콘솔은 켜짐.
var _stamp: PanelContainer = null   # 종이 우상단 스탬프 · 펼침 연출이 끝나며 페이드 인
var _head_nodes: Array = []         # 종이 레터헤드·괘선 · 접힌 밴드에서 눌린 잔상이 보여 함께 페이드 인
var _chrome_nodes: Array = []       # 콘솔 타이틀/하단 바 · 켜짐 연출 후 페이드 인

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func show_doc(input_lines: Array) -> void:
	SfxPlayer.play("arcturus_enter")
	lines_data = input_lines
	# 적응형 · 실제 화면 크기로 기준 갱신 (종이 중앙·하단 안내·스크롤 한계가 화면비 무관).
	var vp: Vector2 = get_viewport().get_visible_rect().size
	VIEWPORT_W = vp.x
	VIEWPORT_H = vp.y
	layer = CanvasLayer.new()
	layer.layer = layer_index
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	# 풀스크린 어두운 배경
	bg = ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04, 0.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)
	# 종이 컨테이너 (화면 가운데 가로 정렬) · 높이는 행을 전부 그려 실측한 뒤 확정한다.
	paper = Control.new()
	paper.position = Vector2((VIEWPORT_W - PAPER_WIDTH) * 0.5, MARGIN_TOP)
	paper.size = Vector2(PAPER_WIDTH, VIEWPORT_H)
	paper.modulate.a = 0.0
	layer.add_child(paper)
	# paper_target_y 초기값을 시작 position과 동기화 · 안 그러면 0(기본값)으로
	# lerp되어 페이드인 0.7s 동안 paper가 화면 위로 빠져나가서 제목이 안 보이고
	# 본문(A 온보딩 등)이 먼저 등장하는 것처럼 보임 (사용자 보고).
	paper_target_y = MARGIN_TOP
	# 문서별 양식(3차 피드백 "각 양식에 맞는 그래픽") · paper: 크림 종이+레터헤드+스탬프 /
	# terminal: 서버 콘솔 / drive: 회수 드라이브 복호화 뷰어(어두운 보라).
	var is_term: bool = style == "terminal"
	var is_drive: bool = style == "drive"
	_setup_palette()
	_kw_color = str(_pal["kw"])
	# 콘솔 계열 양식은 픽셀 터미널 폰트(네오둥근모, OFL) · 사용자 확정 2026-08-31. D2Coding은
	# 한글 자면이 프리텐다드와 구분이 안 돼 교체(실측 · 15차 피드백). 종이는 프리텐다드.
	var mono: FontFile = null
	if is_term or is_drive:
		mono = load("res://assets/fonts/NeoDunggeunmo.ttf")
	paper_visual = ColorRect.new()
	paper_visual.color = _pal["paper"]
	# 종이 양식은 레터헤드·스탬프 확대(4차 피드백 "더 커도 될 것 같다")로 머리 여백을 더 쓴다.
	var head_room: float = 40.0 if (is_term or is_drive) else 68.0
	_head_room = head_room
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
		# 콘솔/뷰어 타이틀 바 · 창 점 3개 + 세션 경로. 화면 밖 스크롤을 따라가지 않게 paper가
		# 아니라 layer(화면 고정)에 붙인다. 텍스트는 기술 표기(영문 경로)라 대사 검수 대상 아님.
		var bar := ColorRect.new()
		bar.color = Color(0.075, 0.095, 0.125, 1.0) if is_term else Color(0.105, 0.075, 0.165, 1.0)
		bar.position = Vector2((VIEWPORT_W - PAPER_WIDTH) * 0.5 - MARGIN_SIDE, 0.0)
		bar.size = Vector2(PAPER_WIDTH + MARGIN_SIDE * 2.0, 30.0)
		bar.modulate.a = 0.0   # 켜짐 연출(_enter_power_on)이 창 점등 후 페이드 인
		_chrome_nodes.append(bar)
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
		path_l.add_theme_font_size_override("font_size", 16)
		path_l.add_theme_color_override("font_color", Color(0.48, 0.75, 0.58) if is_term else Color(0.74, 0.58, 0.96))
		path_l.position = Vector2(0.0, 4.0)
		path_l.size = Vector2(bar.size.x, 22.0)
		path_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bar.add_child(path_l)
		# 은은한 스캔라인 · 4px 간격 수평선(수직 줄무늬 금지 규칙과 별개, CRT 문법은 수평).
		_scan = ColorRect.new()
		_scan.color = Color(1, 1, 1, 1)
		_scan.position = paper_visual.position
		_scan.size = paper_visual.size
		_scan.material = _make_scanline_material()
		paper.add_child(_scan)
		# 콘솔 창 프레임 · 가장자리 1px 라인(4차 피드백 "더 꾸밀 요소"). 스크롤을 따라간다.
		_frame = Panel.new()
		var fr_sb := StyleBoxFlat.new()
		fr_sb.bg_color = Color(0, 0, 0, 0)
		fr_sb.border_color = Color(0.30, 0.55, 0.42, 0.55) if is_term else Color(0.48, 0.36, 0.72, 0.55)
		fr_sb.set_border_width_all(1)
		_frame.add_theme_stylebox_override("panel", fr_sb)
		_frame.position = paper_visual.position
		_frame.size = paper_visual.size
		_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		paper.add_child(_frame)
		# 하단 상태 바 · 세션 정보 + 깜빡이는 블록 커서(터미널 문법). 타이틀 바처럼 화면 고정.
		# 텍스트는 기술 표기(영문)라 대사 검수 대상 아님.
		var foot := ColorRect.new()
		foot.color = bar.color
		foot.position = Vector2(bar.position.x, VIEWPORT_H - 26.0)
		foot.size = Vector2(bar.size.x, 26.0)
		foot.modulate.a = 0.0   # 켜짐 연출 후 페이드 인(타이틀 바와 동시)
		_chrome_nodes.append(foot)
		layer.add_child(foot)
		var foot_l := Label.new()
		if is_term:
			foot_l.text = "svr-03 · READ-ONLY · %d LINES RECOVERED" % input_lines.size()
		else:
			foot_l.text = "drive-A7 · DECRYPT OK · %d ENTRIES" % input_lines.size()
		if mono != null:
			foot_l.add_theme_font_override("font", mono)
		foot_l.add_theme_font_size_override("font_size", 16)
		foot_l.add_theme_color_override("font_color", Color(0.42, 0.62, 0.50) if is_term else Color(0.62, 0.50, 0.82))
		foot_l.position = Vector2(14.0, 4.0)
		foot_l.size = Vector2(foot.size.x - 48.0, 18.0)
		foot.add_child(foot_l)
		var cur := Label.new()
		cur.text = "▮"
		if mono != null:
			cur.add_theme_font_override("font", mono)
		cur.add_theme_font_size_override("font_size", 16)
		cur.add_theme_color_override("font_color", Color(0.45, 0.85, 0.58) if is_term else Color(0.75, 0.55, 1.0))
		cur.position = Vector2(foot.size.x - 26.0, 3.0)
		foot.add_child(cur)
		var ctw := cur.create_tween()
		ctw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		ctw.set_loops()
		ctw.tween_property(cur, "modulate:a", 0.12, 0.5)
		ctw.tween_property(cur, "modulate:a", 1.0, 0.5)
	else:
		# 종이 양식 · 레터헤드(기관명 + 이중 괘선) + 붉은 분류 스탬프. 인사 아카이브 컨셉.
		# 4차 피드백 "레터헤드와 스탬프가 좀 더 커도 될 것 같다" · 19px/20px로 확대.
		var lh := Label.new()
		lh.text = "ARCTURUS · PERSONNEL ARCHIVE"
		lh.add_theme_font_size_override("font_size", 19)
		lh.add_theme_color_override("font_color", Color(0.33, 0.36, 0.48, 0.9))
		lh.position = Vector2(0.0, -60.0)
		lh.modulate.a = 0.0   # 접힌 밴드에서 눌린 잔상 방지 · 펼침 연출과 함께 페이드 인
		_head_nodes.append(lh)
		paper.add_child(lh)
		var rule := ColorRect.new()
		rule.color = Color(0.30, 0.33, 0.45, 0.55)
		rule.position = Vector2(0.0, -28.0)
		rule.size = Vector2(PAPER_WIDTH, 2.0)
		rule.modulate.a = 0.0
		_head_nodes.append(rule)
		paper.add_child(rule)
		var rule2 := ColorRect.new()
		rule2.color = Color(0.30, 0.33, 0.45, 0.35)
		rule2.position = Vector2(0.0, -24.0)
		rule2.size = Vector2(PAPER_WIDTH, 1.0)
		rule2.modulate.a = 0.0
		_head_nodes.append(rule2)
		paper.add_child(rule2)
		_stamp = PanelContainer.new()
		var st_sb := StyleBoxFlat.new()
		st_sb.bg_color = Color(0, 0, 0, 0)
		st_sb.border_color = Color(0.72, 0.18, 0.16, 0.70)
		st_sb.set_border_width_all(3)
		st_sb.content_margin_left = 14.0
		st_sb.content_margin_right = 14.0
		st_sb.content_margin_top = 3.0
		st_sb.content_margin_bottom = 3.0
		_stamp.add_theme_stylebox_override("panel", st_sb)
		_stamp.position = Vector2(PAPER_WIDTH - 225.0, -64.0)
		_stamp.rotation = -0.045
		_stamp.modulate.a = 0.0   # 봉인 펼침 연출(_enter_unfold)이 끝나며 페이드 인
		var st_l := Label.new()
		st_l.text = "RESTRICTED"
		st_l.add_theme_font_size_override("font_size", 20)
		st_l.add_theme_color_override("font_color", Color(0.72, 0.18, 0.16, 0.78))
		_stamp.add_child(st_l)
		paper.add_child(_stamp)
	# 행 배치 · 양식별 머리 행(콘솔 프롬프트·드라이브 복호화 게이지)을 데이터 앞에 붙이고,
	# 각 행을 종류별 서식으로 그린 뒤 실제 높이를 재서 쌓는다(alpha=0 · 타이핑 순서대로 드러남).
	lines_data = _style_preamble() + input_lines
	var y: float = 0.0
	for entry in lines_data:
		var d: Dictionary = entry
		var built: Dictionary = _build_row(d)
		var row: Control = built["row"]
		row.position = Vector2(0.0, y)
		row.modulate.a = 0.0
		rows.append(row)
		labels.append(built["lbl"])
		y += float(built["h"])
	paper.size = Vector2(PAPER_WIDTH, max(y, VIEWPORT_H - MARGIN_TOP * 2.0))
	var vis_size: Vector2 = paper.size + Vector2(MARGIN_SIDE * 2.0, head_room + 40.0)
	paper_visual.size = vis_size
	shadow.size = vis_size
	if _scan != null:
		_scan.size = vis_size
	if _frame != null:
		_frame.size = vis_size
	# 종이 양식 + 장 경계가 있으면 · 한 장 시각을 물리 분리된 종이 3장으로 분해(발췌 사본 픽션).
	if not (is_term or is_drive):
		_layout_paper_sheets(shadow)
	# 배경 페이드 인 → 양식별 등장 연출(5차 피드백 "처음부터 펼쳐져 있지 않게 · 양식에 맞게
	# 펼쳐지거나 켜지게") → 타이핑 시작. 종이 = 봉인 펼침 / 콘솔·뷰어 = 전원 켜짐.
	get_tree().paused = true
	var tw_bg := bg.create_tween()
	tw_bg.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw_bg.tween_property(bg, "color:a", 0.92, 0.5)
	if is_term or is_drive:
		_enter_power_on()
	else:
		_enter_unfold()

# 종이 등장 v3(2026-08-31 사용자 "접힌 편지지·봉인된 봉투같지 않다 · 최소한의 물리 법칙") ·
# 실물 봉투 문법. ① 크라프트 봉투(V자 플랩 + 플랩 꼭짓점 위에 온전히 찍힌 봉인 도장 + 발췌
# 사본 라벨)가 놓이고 ② 봉인이 뜯겨 떨어지면 플랩이 위로 젖혀지고 ③ 접힌 편지 팩(두께 라인 =
# 여러 장 겹침)이 봉투 안에서 미끄러져 나온다 ④ 봉투는 물러나고 팩이 자리 잡은 뒤 접힌 두 단이
# 차례로 젖혀져 펼쳐진다 ⑤ 펼쳐진 순간 미리 인쇄된 서식(레터헤드·스탬프·장 배경)이 이미 보이고,
# 그 위에 본문이 채워진다(타이핑). 접힌 자국은 잠시 남았다 사라진다.
func _enter_unfold() -> void:
	var pw: float = PAPER_WIDTH + MARGIN_SIDE * 2.0
	var px: float = (VIEWPORT_W - PAPER_WIDTH) * 0.5 - MARGIN_SIDE
	var seg_h: float = 210.0
	var top_y: float = MARGIN_TOP - 68.0   # 펼침 후 종이 윗변(head_room 68)과 정렬
	var cream: Color = paper_visual.color
	var wrap := Control.new()   # 봉투 + 접지 팩 · 교차 페이드 후 통째로 제거
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.modulate.a = 0.0
	layer.add_child(wrap)
	# ── 봉투 · 화면 중앙. 자식 순서 = 그리기 순서: 팩(뒤) → 몸통 → 플랩 → 도장(앞) ──
	var env_w: float = 560.0
	var env_h: float = 250.0
	var ex: float = (VIEWPORT_W - env_w) * 0.5
	var ey: float = VIEWPORT_H * 0.5 - env_h * 0.62
	# 접힌 편지 팩 · 봉투 안(몸통에 가려짐)에서 시작해 위로 미끄러져 나온다.
	var pack_w: float = env_w - 70.0
	var pack_h: float = 120.0
	var pack := Control.new()
	pack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pack.position = Vector2(ex + 35.0, ey + 74.0)
	pack.size = Vector2(pack_w, pack_h)
	wrap.add_child(pack)
	var pack_face := ColorRect.new()
	pack_face.color = cream
	pack_face.size = Vector2(pack_w, pack_h)
	pack_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pack.add_child(pack_face)
	# 접힌 두께 · 아래 가장자리에 겹친 장의 라인 두 줄.
	for i in 2:
		var edge := ColorRect.new()
		edge.color = Color(0.55, 0.52, 0.46, 0.85)
		edge.position = Vector2(0.0, pack_h - 3.0 - float(i) * 5.0)
		edge.size = Vector2(pack_w, 2.0)
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pack.add_child(edge)
	# 봉투 몸통 · 크라프트 톤 + 1px 윤곽.
	var env := Panel.new()
	var env_sb := StyleBoxFlat.new()
	env_sb.bg_color = Color(0.80, 0.74, 0.60, 1.0)
	env_sb.border_color = Color(0.48, 0.42, 0.30, 0.9)
	env_sb.set_border_width_all(1)
	env.add_theme_stylebox_override("panel", env_sb)
	env.position = Vector2(ex, ey)
	env.size = Vector2(env_w, env_h)
	env.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(env)
	# 봉투 라벨 · 발췌 사본 픽션(세 문서가 한 봉투에 묶인 이유 = 감시팀이 추린 사본 묶음).
	var env_lab := Label.new()
	env_lab.text = "발췌 사본 · 3매 · 감시팀"
	env_lab.add_theme_font_size_override("font_size", 15)
	env_lab.add_theme_color_override("font_color", Color(0.35, 0.29, 0.18, 0.85))
	env_lab.position = Vector2(22.0, env_h - 36.0)
	env.add_child(env_lab)
	# V자 플랩 · 접선(봉투 윗변)이 pivot. 젖힘 = scale.y 반전(위로 뒤집힘).
	var flap := Polygon2D.new()
	flap.polygon = PackedVector2Array([Vector2(0.0, 0.0), Vector2(env_w, 0.0), Vector2(env_w * 0.5, 148.0)])
	flap.color = Color(0.74, 0.67, 0.52, 1.0)
	flap.position = Vector2(ex, ey)
	wrap.add_child(flap)
	# 봉인 도장 · 플랩 꼭짓점 위에 온전히 올라앉는다(반걸침·공중부양 금지 · 15차).
	var seal := PanelContainer.new()
	var sl_sb := StyleBoxFlat.new()
	sl_sb.bg_color = Color(0.92, 0.90, 0.84, 1.0)
	sl_sb.border_color = Color(0.72, 0.18, 0.16, 0.85)
	sl_sb.set_border_width_all(4)
	sl_sb.content_margin_left = 20.0
	sl_sb.content_margin_right = 20.0
	sl_sb.content_margin_top = 6.0
	sl_sb.content_margin_bottom = 6.0
	seal.add_theme_stylebox_override("panel", sl_sb)
	var seal_l := Label.new()
	seal_l.text = "RESTRICTED"
	seal_l.add_theme_font_size_override("font_size", 28)
	seal_l.add_theme_color_override("font_color", Color(0.72, 0.18, 0.16, 0.9))
	seal.add_child(seal_l)
	seal.rotation = -0.05
	seal.modulate.a = 0.0
	seal.scale = Vector2(1.7, 1.7)
	# 도장 중심 = 플랩 꼭짓점 근처(플랩+몸통 면 위 · 크기 확정 후 중심 정렬).
	seal.resized.connect(func() -> void:
		seal.pivot_offset = seal.size / 2.0
		seal.position = Vector2(ex + env_w * 0.5, ey + 142.0) - seal.size / 2.0)
	wrap.add_child(seal)
	# ── 펼침용 아랫단 2·3 · 위 접선 pivot에서 scale.y 0→1로 젖혀진다(기존 삼단 문법) ──
	var segs: Array = []
	for i in 2:
		var seg := ColorRect.new()
		seg.color = cream
		seg.position = Vector2(px, top_y + seg_h * float(i + 1))
		seg.size = Vector2(pw, seg_h)
		seg.pivot_offset = Vector2(pw * 0.5, 0.0)
		seg.scale = Vector2(1.0, 0.0)
		seg.modulate = Color(0.72, 0.70, 0.66)
		wrap.add_child(seg)
		var crease := ColorRect.new()
		crease.color = Color(0.35, 0.32, 0.28, 0.30)
		crease.position = Vector2.ZERO
		crease.size = Vector2(pw, 7.0)
		seg.add_child(crease)
		segs.append(seg)
	# 펼친 실제 종이에 남는 접힌 자국 · 잠시 보였다 사라진다(paper 로컬 y = 화면 - MARGIN_TOP).
	var remnants: Array = []
	for i in 2:
		var line := ColorRect.new()
		line.color = Color(0.40, 0.37, 0.32, 0.20)
		line.position = Vector2(-MARGIN_SIDE, top_y + seg_h * float(i + 1) - MARGIN_TOP)
		line.size = Vector2(pw, 2.0)
		line.modulate.a = 0.0
		paper.add_child(line)
		remnants.append(line)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	# ① 봉투 페이드 인 → 도장 내려찍힘 → 반 박자 봉인 상태.
	tw.tween_property(wrap, "modulate:a", 1.0, 0.25)
	tw.tween_property(seal, "modulate:a", 1.0, 0.10)
	tw.parallel().tween_property(seal, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.55)
	# ② 봉인 뜯김(아래로 떨어져 나감 · 기존 자산 대타 SFX) + 봉투 반동 + 플랩 젖힘.
	tw.tween_callback(func() -> void: SfxPlayer.play("hatch_open", -4.0))
	tw.tween_property(seal, "rotation", 0.55, 0.32)
	tw.parallel().tween_property(seal, "position", Vector2(ex + env_w * 0.5 - 40.0, ey + 240.0), 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(seal, "modulate:a", 0.0, 0.32)
	tw.parallel().tween_property(flap, "scale:y", -0.5, 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(flap, "modulate", Color(0.55, 0.50, 0.40), 0.30)
	tw.tween_interval(0.12)
	# ③ 접힌 편지 팩이 봉투에서 미끄러져 나온다(하단은 봉투 몸통에 가려진 채).
	tw.tween_property(pack, "position:y", ey - pack_h - 26.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(flap, "modulate:a", 0.0, 0.30)
	# ④ 봉투 퇴장 + 팩이 문서 자리로 이동·확대(접힌 팩 상단면이 된다).
	tw.tween_property(env, "position:y", ey + 150.0, 0.40).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(env, "modulate:a", 0.0, 0.38)
	tw.parallel().tween_property(pack, "position", Vector2(px, top_y), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(pack, "scale", Vector2(pw / pack_w, seg_h / pack_h), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_interval(0.10)
	# ⑤ 1단 젖힘(뒷면이 밝아지며 내려온다) → 2단 젖힘.
	tw.tween_property(segs[0], "scale:y", 1.0, 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(segs[0], "modulate", Color.WHITE, 0.36)
	tw.tween_property(segs[1], "scale:y", 1.0, 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(segs[1], "modulate", Color.WHITE, 0.30)
	# ⑥ 실제 종이로 교차 페이드 · 인쇄된 서식(레터헤드·스탬프·장 배경)은 이 순간 이미 보인다.
	tw.tween_property(paper, "modulate:a", 1.0, 0.16)
	tw.parallel().tween_property(wrap, "modulate:a", 0.0, 0.22)
	if _stamp != null:
		tw.parallel().tween_property(_stamp, "modulate:a", 1.0, 0.20)
	for hn in _head_nodes:
		if hn != null and is_instance_valid(hn):
			tw.parallel().tween_property(hn, "modulate:a", 1.0, 0.20)
	for rn in remnants:
		tw.parallel().tween_property(rn, "modulate:a", 1.0, 0.16)
	tw.tween_callback(wrap.queue_free)
	tw.tween_callback(_start_typing)
	# 접힌 자국은 읽기 시작하면 천천히 사라진다.
	for rn in remnants:
		var rt := (rn as ColorRect).create_tween()
		rt.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		rt.tween_interval(2.2)
		rt.tween_property(rn, "modulate:a", 0.0, 1.6)

# 콘솔·뷰어 등장 · 수평 점화선이 번쩍이고 창이 세로로 켜진다(CRT 전원 문법) + 부팅 플리커.
# 플리커는 저진폭 2회(광과민 고려)이며 화면 효과 옵션이 꺼져 있으면 생략.
func _enter_power_on() -> void:
	# 창은 점화선 번쩍임 직후에야 보인다(그 전까지 alpha 0 · 꺼진 화면).
	paper.pivot_offset = Vector2(PAPER_WIDTH * 0.5, VIEWPORT_H * 0.38 - MARGIN_TOP)
	paper.scale = Vector2(1.0, 0.015)
	var ign := ColorRect.new()
	ign.color = Color(0.70, 1.0, 0.85, 0.0) if style == "terminal" else Color(0.85, 0.70, 1.0, 0.0)
	ign.position = Vector2((VIEWPORT_W - PAPER_WIDTH) * 0.5 - MARGIN_SIDE, VIEWPORT_H * 0.38 - 1.5)
	ign.size = Vector2(PAPER_WIDTH + MARGIN_SIDE * 2.0, 3.0)
	layer.add_child(ign)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_interval(0.3)
	tw.tween_property(ign, "color:a", 0.9, 0.07)
	tw.tween_callback(func() -> void: paper.modulate.a = 1.0)
	tw.tween_property(paper, "scale:y", 1.0, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(ign, "color:a", 0.0, 0.22)
	if GameState.screen_fx_enabled:
		tw.tween_property(paper, "modulate:a", 0.72, 0.05)
		tw.tween_property(paper, "modulate:a", 1.0, 0.06)
		tw.tween_property(paper, "modulate:a", 0.85, 0.05)
		tw.tween_property(paper, "modulate:a", 1.0, 0.07)
	# 타이틀/하단 바 · 창이 켜진 뒤 함께 점등.
	for c in _chrome_nodes:
		if c != null and is_instance_valid(c):
			tw.parallel().tween_property(c, "modulate:a", 1.0, 0.25)
	tw.tween_callback(ign.queue_free)
	tw.tween_callback(_start_typing)

# ── 양식 팔레트 · 종이(크림 위 진청) / 콘솔(어두운 청록 위 녹색·호박) / 뷰어(보라) ──────────
func _setup_palette() -> void:
	match style:
		"terminal":
			_pal = {
				"paper": Color(0.043, 0.055, 0.075, 0.97), "body": Color(0.72, 0.80, 0.78),
				"dim": Color(0.42, 0.58, 0.50), "title": Color(0.45, 0.85, 0.58),
				"rule": Color(0.30, 0.55, 0.42, 0.55), "tint": Color(0.30, 0.55, 0.42, 0.10),
				"redact": Color(0.16, 0.21, 0.22), "kw": "#ffc857", "accent": Color(0.45, 0.85, 0.58),
				"bad": Color(0.85, 0.36, 0.32),
			}
		"drive":
			_pal = {
				"paper": Color(0.055, 0.042, 0.085, 0.97), "body": Color(0.80, 0.75, 0.90),
				"dim": Color(0.56, 0.48, 0.70), "title": Color(0.75, 0.55, 1.0),
				"rule": Color(0.48, 0.36, 0.72, 0.55), "tint": Color(0.48, 0.36, 0.72, 0.12),
				"redact": Color(0.19, 0.15, 0.26), "kw": "#c9a2ff", "accent": Color(0.75, 0.55, 1.0),
				"bad": Color(0.85, 0.36, 0.32),
			}
		_:
			_pal = {
				"paper": Color(0.92, 0.90, 0.84, 0.96), "body": Color(0.10, 0.12, 0.18),
				"dim": Color(0.45, 0.45, 0.55), "title": Color(0.18, 0.20, 0.28),
				"rule": Color(0.30, 0.33, 0.45, 0.55), "tint": Color(0.30, 0.33, 0.45, 0.08),
				"redact": Color(0.12, 0.12, 0.14), "kw": "#0a4a73", "accent": Color(0.33, 0.36, 0.48),
				"bad": Color(0.72, 0.18, 0.16),
			}
	if style == "terminal" or style == "drive":
		# 픽셀 폰트(네오둥근모)는 embolden 합성이 픽셀을 뭉갠다 · 굵기 없이 색으로만 위계.
		_font_main = load("res://assets/fonts/NeoDunggeunmo.ttf")
		_font_bold = _font_main
	else:
		_font_main = load("res://assets/fonts/Pretendard-Regular.otf")
		# 굵은 글꼴은 별도 파일이 없어 합성(embolden) · 제목·라벨 열·프롬프트에만 쓴다.
		var fv := FontVariation.new()
		fv.base_font = _font_main
		fv.variation_embolden = 0.55
		_font_bold = fv

func _c(key: String) -> Color:
	return _pal[key]

# 콘솔 계열은 픽셀 폰트(네오둥근모 · 16px 격자)라 크기를 16/32 정수 배로 스냅한다.
# 비정수 배 스케일은 픽셀이 불균일하게 깨진다. 실제 터미널처럼 본문은 단일 크기(16)로 눌러
# "너무 잘 정리된" 위계를 지운다(15차 피드백). 종이 양식은 그대로 통과.
func _fs(px: int) -> int:
	if style == "terminal" or style == "drive":
		return 32 if px >= 24 else 16
	return px

func _hex(key: String) -> String:
	return "#" + (_pal[key] as Color).to_html(false)

# 양식별 머리 행 · 데이터(대사집 단일 소스) 밖의 기술 표기만 붙인다(영문 · 검수 대상 아님).
# 15차 리뉴얼(2026-08-31 사용자 확정): 콘솔 = 접속 배너 + 일상 잡음 로그가 고속 덤프로 좌라락
# 지나간 뒤(해킹 화면 클리셰) 복구 로그(단일 소스)가 제 속도로 나온다. 뷰어 = 의미 없는 암호문
# 헥스가 빠르게 지나가고 DECRYPT 게이지가 차오른 뒤에야 평문 리드아웃(복호화가 지금 일어난다).
# 옛 ELF 매직·VEIL 아스키 바이트는 폐기: 비개발자가 읽을 수 없고 서명 공개를 스포일한다(15차).
func _style_preamble() -> Array:
	match style:
		"terminal":
			var out: Array = []
			# 접속 배너 · figlet 문법(ASCII만 · 박스 문자는 폰트 커버리지 리스크).
			for ln in [
				"    _    ____   ____ _____ _   _ ____  _   _ ____",
				"   / \\  |  _ \\ / ___|_   _| | | |  _ \\| | | / ___|",
				"  / _ \\ | |_) | |     | | | | | | |_) | | | \\___ \\",
				" / ___ \\|  _ <| |___  | | | |_| |  _ <| |_| |___) |",
				"/_/   \\_\\_| \\_\\\\____| |_|  \\___/|_| \\_\\\\___/|____/",
			]:
				out.append({"kind": "hex", "text": ln, "fast": true, "delay": 0.03})
			out.append({"kind": "hex", "text": "svr-03 · restricted shell · unauthorized access is logged", "fast": true, "delay": 0.3})
			out.append({"kind": "blank", "text": "", "h": 12.0, "delay": 0.15})
			out.append({"kind": "prompt", "text": "tail -n 200 /var/log/veil.d/recovered.log", "delay": 0.55})
			# 일상 잡음 로그 · 백업·온도·인증 실패 같은 무해한 운영 기록이 빠르게 흘러가
			# "정리된 문서"가 아니라 "살아 있던 서버의 로그"로 읽히게 한다.
			for noise in [
				["03:38:12", "INFO", "rotate: /var/log/veil.d/audit.log -> audit.log.1 (ok)"],
				["03:38:12", "INFO", "backup: incremental snapshot committed (delta 412 MB)"],
				["03:38:40", "WARN", "thermal: rack B-07 intake 41.2 C (threshold 40.0)"],
				["03:38:41", "INFO", "thermal: fan profile -> MAX"],
				["03:39:03", "INFO", "auth: session opened for maint-bot (key)"],
				["03:39:05", "INFO", "watchdog: heartbeat ok (3/3)"],
				["03:39:27", "WARN", "auth: 4 failed password attempts (source: internal)"],
				["03:39:31", "INFO", "auth: lockout window applied (300 s)"],
				["03:39:44", "INFO", "s\u2592\u2593\u2591d: \u2592\u2593 job re\u2591\u2592med ok"],
				["03:40:02", "INFO", "cron: purge-tmp finished (2913 files)"],
				["03:40:19", "INFO", "watchdog: heartbeat ok (3/3)"],
				["03:40:44", "WARN", "fsck: orphaned inode chain at 0x7fa2c relinked"],
				["03:40:58", "INFO", "audit: integrity sweep started (scope: veil.d)"],
				["03:41:00", "ERR", "audit: checksum mismatch in 3 segments"],
				["03:41:02", "INFO", "recover: journal replay \u2592\u2591\u2593 partial"],
			]:
				var nr: Array = noise
				out.append({"kind": "log", "ts": str(nr[0]), "lvl": str(nr[1]), "text": str(nr[2]), "fast": true, "delay": 0.05})
			return out
		"drive":
			var out: Array = []
			# 암호문 덤프 · 해독 전이라 바이트도 문자열 열도 전부 쓰레기(읽라고 있는 줄이 아니다).
			for i in 6:
				var line: String = "%04x  " % (i * 16)
				var asc: String = ""
				for j in 16:
					line += "%02x " % (randi() % 256)
					if j == 7:
						line += " "
					var g: int = randi() % 93 + 33
					asc += char(g)
				out.append({"kind": "hex", "text": "%s |%s|" % [line, asc], "fast": true, "delay": 0.06})
			out.append({"kind": "bar", "text": "DECRYPT", "delay": 1.7})
			out.append({"kind": "rule", "delay": 0.3})
			return out
	return []

# ── 행 빌더 · 행 컨테이너 + 타이핑 대상 RichTextLabel + 실측 높이 ────────────────────────
func _rtl(parent: Control, x: float, y: float, w: float, px: int, col: Color, bb: String) -> RichTextLabel:
	px = _fs(px)
	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.scroll_active = false
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 타이핑 중 줄바꿈·정렬이 흔들리지 않게 · 숨긴 글자도 자리를 차지한다.
	lbl.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	lbl.add_theme_font_override("normal_font", _font_main)
	lbl.add_theme_font_override("bold_font", _font_bold)
	lbl.add_theme_font_size_override("normal_font_size", px)
	lbl.add_theme_font_size_override("bold_font_size", px)
	lbl.add_theme_color_override("default_color", col)
	lbl.position = Vector2(x, y)
	lbl.size = Vector2(w, 10.0)
	lbl.text = bb
	lbl.visible_characters = 0
	parent.add_child(lbl)
	var ch: float = lbl.get_content_height()
	if ch <= 0.0:
		ch = float(px) * 1.45
	lbl.size = Vector2(w, ch)
	return lbl

func _lab(parent: Control, x: float, y: float, w: float, px: int, col: Color, text: String, bold: bool = false, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	px = _fs(px)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font_bold if bold else _font_main)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.position = Vector2(x, y)
	l.size = Vector2(w, float(px) * 1.5)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _rect(parent: Control, x: float, y: float, w: float, h: float, col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.position = Vector2(x, y)
	r.size = Vector2(w, h)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r

func _build_row(d: Dictionary) -> Dictionary:
	var kind: String = str(d.get("kind", "body"))
	var text: String = str(d.get("text", ""))
	var is_paper: bool = not (style == "terminal" or style == "drive")
	var row := Control.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size = Vector2(PAPER_WIDTH, 10.0)
	paper.add_child(row)
	var lbl: RichTextLabel = null
	var h: float = 0.0
	match kind:
		"title":
			var px: int = 30 if is_paper else (24 if style == "terminal" else 28)
			var bb: String = _to_bbcode(text)
			if style == "terminal":
				bb = "[color=%s]==> [/color]%s[color=%s] <==[/color]" % [_hex("dim"), bb, _hex("dim")]
			lbl = _rtl(row, 0.0, 10.0, PAPER_WIDTH, px, _c("title"), bb)
			h = lbl.size.y + 22.0
		"blank":
			lbl = _rtl(row, 0.0, 0.0, PAPER_WIDTH, 16, _c("body"), "")
			h = float(d.get("h", 20.0))
		"rule":
			_rect(row, 0.0, 6.0, PAPER_WIDTH, 1.0, _c("rule"))
			lbl = _rtl(row, 0.0, 0.0, PAPER_WIDTH, 16, _c("body"), "")
			h = 14.0
		"speaker":
			lbl = _rtl(row, 0.0, 6.0, PAPER_WIDTH, 18, _c("dim"), _to_bbcode(text))
			h = lbl.size.y + 14.0
		"section":
			# 하위 문서 머리 · 실물 메모의 "큰 문서명 + 괘선" 구도. 태그 상자(A/B/C)는 제목 줄 왼쪽에.
			# 종류 배지(badge)는 제목과 낱말이 겹쳐 폐지(14차 판정) · 값이 있으면 옛 두 줄 구도로 그린다.
			var tag: String = str(d.get("tag", ""))
			var badge: String = str(d.get("badge", ""))
			var x: float = 0.0
			var title_y: float = 36.0 if badge != "" else 8.0
			var title_x: float = 0.0 if (badge != "" or tag == "") else 44.0
			if tag != "":
				var box := PanelContainer.new()
				var sb := StyleBoxFlat.new()
				sb.bg_color = Color(0, 0, 0, 0)
				sb.border_color = _c("accent")
				sb.set_border_width_all(2)
				sb.content_margin_left = 8.0
				sb.content_margin_right = 8.0
				sb.content_margin_top = 1.0
				sb.content_margin_bottom = 1.0
				box.add_theme_stylebox_override("panel", sb)
				box.position = Vector2(0.0, 8.0 if badge != "" else title_y + 7.0)
				box.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var tl := Label.new()
				tl.text = tag
				tl.add_theme_font_override("font", _font_bold)
				tl.add_theme_font_size_override("font_size", 15)
				tl.add_theme_color_override("font_color", _c("accent"))
				box.add_child(tl)
				row.add_child(box)
				x = 44.0
			if badge != "":
				_lab(row, x, 8.0, PAPER_WIDTH - x, 16, _c("dim"), badge)
			lbl = _rtl(row, title_x, title_y, PAPER_WIDTH - title_x, 26, _c("title"), "[b]%s[/b]" % _to_bbcode(text))
			_rect(row, 0.0, title_y + lbl.size.y + 8.0, PAPER_WIDTH, 2.0, _c("rule"))
			h = title_y + lbl.size.y + 24.0
		"kv":
			# 라벨: 값 · 라벨 열 고정폭(메모 머리 블록 TO/FROM/SUBJECT 실측: 라벨 12% · 값 이어서).
			var col_w: float = float(d.get("col", 150.0 if is_paper else 200.0))
			var lab_px: int = 17
			var val_px: int = 22 if is_paper else 21
			_lab(row, 0.0, 6.0, col_w - 10.0, lab_px, _c("dim"), str(d.get("label", "")), true)
			var vw: float = PAPER_WIDTH - col_w
			if d.has("right_label"):
				vw = 560.0 - col_w
				_lab(row, 560.0, 6.0, 90.0, lab_px, _c("dim"), str(d.get("right_label", "")), true)
				_rtl(row, 650.0, 2.0, PAPER_WIDTH - 650.0, val_px, _c("body"), _to_bbcode(str(d.get("right_text", "")))).visible_characters = -1
			lbl = _rtl(row, col_w, 2.0, vw, val_px, _c("body"), _to_bbcode(text))
			h = max(lbl.size.y, 28.0) + 8.0 + float(d.get("gap", 0.0))
		"form":
			# 표 행 · 회의록/대장 서식(한국 공문 회의록: 일시·장소·참석자·안건 표) · 라벨 칸 음영 + 괘선.
			var col_w: float = float(d.get("col", 170.0))
			var cell: ColorRect = _rect(row, 0.0, 0.0, col_w, 10.0, _c("tint"))   # 높이는 실측 후 갱신
			_rect(row, 0.0, 0.0, PAPER_WIDTH, 1.0, _c("rule"))
			_lab(row, 14.0, 8.0, col_w - 20.0, 17, _c("dim"), str(d.get("label", "")), true)
			lbl = _rtl(row, col_w + 14.0, 5.0, PAPER_WIDTH - col_w - 24.0, 21, _c("body"), _to_bbcode(text))
			h = max(lbl.size.y, 28.0) + 12.0
			cell.size.y = h
			_rect(row, 0.0, 0.0, 1.0, h, _c("rule"))
			_rect(row, col_w, 0.0, 1.0, h, _c("rule"))
			_rect(row, PAPER_WIDTH - 1.0, 0.0, 1.0, h, _c("rule"))
			if bool(d.get("last", false)):
				_rect(row, 0.0, h - 1.0, PAPER_WIDTH, 1.0, _c("rule"))
				h += 6.0
		"para":
			# 문단 · 블록체(실물 메모: 들여쓰기 없이 문단 사이 한 줄 간격). 양끝 정렬([fill])은 한 줄짜리
			# 문장도 글자 단위로 벌려 놓아(실측) 쓰지 않는다.
			lbl = _rtl(row, 0.0, 2.0, PAPER_WIDTH, 23, _c("body"), _to_bbcode(text))
			h = lbl.size.y + 18.0
		"num":
			# 번호 항목 · 번호 열 + 내어쓰기(감긴 줄도 본문 열에 맞춘다).
			_lab(row, 6.0, 2.0, 34.0, 22, _c("body"), str(d.get("n", "·")))
			lbl = _rtl(row, 44.0, 2.0, PAPER_WIDTH - 44.0, 23, _c("body"), _to_bbcode(text))
			h = lbl.size.y + 12.0
		"note":
			# 비고·결론 상자 · 1px 윤곽선 상자(음영·왼쪽 강조 띠 없음 · 14차 판정 "색 띠 상자는 AI 생성 느낌")
			# + 작은 라벨 위, 본문 아래. 서식 표의 괘선과 같은 선으로 그려 문서 안의 '붙임 상자'처럼 읽힌다.
			var lab: String = str(d.get("label", "비고"))
			lbl = _rtl(row, 18.0, 32.0, PAPER_WIDTH - 36.0, 21, _c("body"), _to_bbcode(text))
			h = 32.0 + lbl.size.y + 12.0
			var box := Panel.new()
			var bsb := StyleBoxFlat.new()
			bsb.bg_color = Color(0, 0, 0, 0)
			bsb.border_color = _c("rule")
			bsb.set_border_width_all(1)
			box.add_theme_stylebox_override("panel", bsb)
			box.position = Vector2.ZERO
			box.size = Vector2(PAPER_WIDTH, h)
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(box)
			row.move_child(box, 0)
			_lab(row, 18.0, 8.0, 300.0, 15, _c("dim"), lab, true)
			h += 10.0
		"sign":
			# 서명 블록 · 중앙 우측(실물 메모의 서명 위치 · 폭의 55%~85%) + 서명선 + 작은 부기.
			_rect(row, 600.0, 22.0, 240.0, 1.0, _c("rule"))
			lbl = _rtl(row, 480.0, 30.0, 360.0, 22, _c("body"), "[right]%s[/right]" % _to_bbcode(text))
			h = 30.0 + lbl.size.y + 6.0
			var sub: String = str(d.get("sub", ""))
			if sub != "":
				var sl: RichTextLabel = _rtl(row, 380.0, h, 460.0, 15, _c("dim"), "[right]%s[/right]" % _to_bbcode(sub))
				sl.visible_characters = -1
				h += sl.size.y + 4.0
			h += 6.0
		"redacted":
			# 통째로 지워진 줄 · 검열 바(글자는 바와 같은 색이라 보이지 않는다).
			var bw: float = PAPER_WIDTH * float(d.get("w", 0.62))
			_rect(row, 0.0, 8.0, bw, 24.0, _c("redact"))
			lbl = _rtl(row, 8.0, 8.0, bw - 16.0, 18, _c("redact"), text.replace("[", "").replace("]", ""))
			h = 44.0
		"sheet":
			# 장 경계 · 종이 양식은 여기서 장 배경 자체가 끊긴다(_layout_paper_sheets가 이 행의
			# y를 경계로 물리적으로 분리된 종이 3장을 깐다 · 15차). 행 자체는 빈 틈만 남긴다.
			if not is_paper:
				_rect(row, 0.0, 22.0, PAPER_WIDTH, 1.0, _c("rule"))
			lbl = _rtl(row, 0.0, 0.0, PAPER_WIDTH, 16, _c("body"), "")
			h = 72.0 if is_paper else 46.0
		"prompt":
			_lab(row, 0.0, 4.0, 110.0, 18, _c("accent"), "svr-03:~$", true)
			lbl = _rtl(row, 104.0, 2.0, PAPER_WIDTH - 104.0, 18, _c("body"), _to_bbcode(text))
			h = lbl.size.y + 14.0
		"log":
			# 로그 행 · 시각 열 + 등급 태그 + 메시지(syslog 문법: 시각·등급·메시지 열 정렬).
			var lvl: String = str(d.get("lvl", "INFO"))
			var lc: Color = _c("dim")
			match lvl:
				"WARN":
					lc = Color(1.0, 0.78, 0.34)
				"ALRT", "ERR", "CRIT":
					lc = Color(1.0, 0.42, 0.38)
				"NOTE":
					lc = Color(0.50, 0.80, 0.90)
			var ts_l: Label = _lab(row, 0.0, 3.0, 90.0, 16, _c("dim"), str(d.get("ts", "")))
			_lab(row, 96.0, 3.0, 60.0, 16, lc, lvl, true)
			# live 행 · 드러나는 순간 ts를 실제 현재 시각으로 채운다(_reveal_row) = 이 줄은
			# 복구된 과거가 아니라 지금 쓰이고 있다.
			if bool(d.get("live", false)):
				row.set_meta("live_ts", ts_l)
			lbl = _rtl(row, 164.0, 2.0, PAPER_WIDTH - 164.0, 20, _c("body"), _to_bbcode(text))
			# 행간 타이트 · 성기면 "정리된 문서"로 읽힌다(콘솔 밀도 = 15차 의도).
			h = max(lbl.size.y, 22.0) + 4.0
		"corrupt":
			# 덮어쓰인 구간 · 깨진 블록 문자 띠(rows 겹) 위에 복구 불가 표시(어두운 적색).
			var glyphs: String = "▒▓░█▒░"
			var band_rows: int = int(d.get("rows", 1))
			var yy: float = 4.0
			for r in band_rows:
				var noise: String = ""
				for i in 64:
					noise += glyphs[randi() % glyphs.length()]
				var nl: Label = _lab(row, 0.0, yy, PAPER_WIDTH, 15, Color(_c("bad"), 0.45), noise)
				nl.clip_text = true
				yy += 22.0
			lbl = _rtl(row, 0.0, yy + 2.0, PAPER_WIDTH, 18, _c("bad"), "[center]%s[/center]" % _to_bbcode(text))
			h = yy + 2.0 + lbl.size.y + 12.0
		"gap":
			# 손상 구간 건너뜀 · 복구 도구가 남기는 생략 표기(로그 흐름이 여기서 끊겼다).
			lbl = _rtl(row, 0.0, 8.0, PAPER_WIDTH, 16, _c("dim"), "[center]· · ·  %s  · · ·[/center]" % _to_bbcode(text))
			h = lbl.size.y + 20.0
		"cut":
			# 발췌 절단부 · 절취 점선 + 표기. 원본에서 이 아래를 잘라냈다는 자리(발췌 사본 픽션).
			var dash_x: float = 0.0
			while dash_x < PAPER_WIDTH - 10.0:
				_rect(row, dash_x, 10.0, 14.0, 1.0, _c("rule"))
				dash_x += 24.0
			lbl = _rtl(row, 0.0, 20.0, PAPER_WIDTH, 15, _c("dim"), "[center]%s[/center]" % _to_bbcode(text))
			h = 20.0 + lbl.size.y + 10.0
		"bar":
			# 복호화 게이지 · 드러날 때 0→100%로 차오르고 %가 카운트업(_reveal_row).
			_lab(row, 0.0, 4.0, 110.0, 16, _c("dim"), text, true)
			_rect(row, 110.0, 9.0, 560.0, 12.0, _c("tint"))
			var fill: ColorRect = _rect(row, 110.0, 9.0, 0.0, 12.0, _c("accent"))
			row.set_meta("bar_fill", fill)
			row.set_meta("bar_w", 560.0)
			var pct: Label = _lab(row, 684.0, 4.0, 160.0, 16, _c("accent"), "0%")
			row.set_meta("bar_pct", pct)
			lbl = _rtl(row, 0.0, 0.0, PAPER_WIDTH, 16, _c("body"), "")
			h = 32.0
		"hex":
			lbl = _rtl(row, 0.0, 2.0, PAPER_WIDTH, 15, _c("dim"), _to_bbcode(text))
			h = lbl.size.y + 4.0
		_:
			lbl = _rtl(row, 0.0, 2.0, PAPER_WIDTH, 23, _c("body"), _to_bbcode(text))
			h = max(lbl.size.y, 32.0) + 14.0
	row.size = Vector2(PAPER_WIDTH, h)
	return {"row": row, "lbl": lbl, "h": h}

# 종이 양식 + 장 경계(sheet)가 있으면 한 장 시각을 물리적으로 분리된 종이 3장으로 분해한다
# (발췌 사본 픽션 · 15차 "왜 세 문서가 한 봉투·한 장에 묶였는지, 크기가 왜 다른지"). 장마다
# 폭·좌우 오프셋·색조가 미묘하게 달라 "출처가 다른 원본에서 발췌한 사본 묶음"으로 읽힌다.
func _layout_paper_sheets(shadow: ColorRect) -> void:
	var bounds: Array = []
	for i in lines_data.size():
		if str((lines_data[i] as Dictionary).get("kind", "")) == "sheet":
			bounds.append((rows[i] as Control).position.y)
	if bounds.is_empty():
		return
	# 기존 "한 장" 시각·그림자 제거 → 장별 종이 + 그림자로 대체.
	paper_visual.visible = false
	shadow.visible = false
	var tops: Array = [-_head_room]
	var bots: Array = []
	for b in bounds:
		bots.append(float(b) + 8.0)
		tops.append(float(b) + 54.0)
	bots.append(paper.size.y + 28.0)
	var offs: Array = [0.0, 16.0, -7.0]
	var wdel: Array = [0.0, -30.0, -12.0]
	var tint: Array = [
		Color(0.92, 0.90, 0.84, 0.96),
		Color(0.90, 0.86, 0.78, 0.96),
		Color(0.91, 0.90, 0.86, 0.96),
	]
	for s in tops.size():
		var idx: int = mini(s, 2)
		var sx: float = -MARGIN_SIDE + float(offs[idx])
		var sw: float = PAPER_WIDTH + MARGIN_SIDE * 2.0 + float(wdel[idx])
		var sy: float = float(tops[s])
		var sh: float = float(bots[s]) - sy
		var sh_rect := ColorRect.new()
		sh_rect.color = Color(0.0, 0.0, 0.0, 0.18)
		sh_rect.position = Vector2(sx - 6.0, sy + 6.0)
		sh_rect.size = Vector2(sw, sh)
		sh_rect.z_index = -1
		sh_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		paper.add_child(sh_rect)
		var sheet_bgr := ColorRect.new()
		sheet_bgr.color = tint[idx]
		sheet_bgr.position = Vector2(sx, sy)
		sheet_bgr.size = Vector2(sw, sh)
		sheet_bgr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		paper.add_child(sheet_bgr)
		paper.move_child(sheet_bgr, 2)   # paper_visual·shadow 다음 · 모든 행/레터헤드보다 뒤
		# 장 윗변 하이라이트 · 빛 받는 모서리(장이 낱장임을 보이는 최소 신호).
		var hl := ColorRect.new()
		hl.color = Color(1.0, 1.0, 1.0, 0.30)
		hl.position = Vector2(sx, sy)
		hl.size = Vector2(sw, 1.0)
		hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		paper.add_child(hl)
		paper.move_child(hl, 3)

# 행 드러내기 · 컨테이너째 보이고, 게이지 행은 차오르는 연출 + % 카운트업, live 행은 ts를
# 실제 현재 시각으로 채운다(지금 쓰이고 있는 줄 · 15차).
func _reveal_row(i: int) -> void:
	if i < 0 or i >= rows.size():
		return
	var row: Control = rows[i]
	row.modulate.a = 1.0
	if row.has_meta("live_ts"):
		var td: Dictionary = Time.get_time_dict_from_system()
		(row.get_meta("live_ts") as Label).text = "%02d:%02d:%02d" % [int(td["hour"]), int(td["minute"]), int(td["second"])]
	if row.has_meta("bar_fill"):
		var fill: ColorRect = row.get_meta("bar_fill")
		var pct: Label = row.get_meta("bar_pct")
		var tw := fill.create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_property(fill, "size:x", float(row.get_meta("bar_w")), 1.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_method(func(v: float) -> void:
			if is_instance_valid(pct):
				pct.text = "%d%%" % int(v)
		, 0.0, 100.0, 1.3)
		tw.tween_callback(func() -> void:
			if is_instance_valid(pct):
				pct.text = "100%  OK")

# 글자가 없는 행(괘선·장 경계·게이지)은 타이핑 없이 delay만 두고 지나간다.
func _is_static_row(i: int) -> bool:
	if i < 0 or i >= labels.size():
		return true
	return (labels[i] as RichTextLabel).get_total_character_count() == 0

# 하니스용 · 특정 행이 화면 위쪽에 오도록 종이를 즉시 되감는다.
func scroll_to_line(idx: int) -> void:
	if idx < 0 or idx >= rows.size():
		return
	paper_target_y = MARGIN_TOP - (rows[idx] as Control).position.y + 8.0
	var min_y: float = -(paper.size.y - VIEWPORT_H + MARGIN_TOP * 2.0)
	if min_y > MARGIN_TOP:
		min_y = MARGIN_TOP
	paper_target_y = clamp(paper_target_y, min_y, MARGIN_TOP)
	paper.position.y = paper_target_y

# [[키워드]] -> 강조색 bbcode · [REDACTED] -> 검열 바 · 그 밖의 대괄호는 [lb]로 이스케이프해 그대로.
func _to_bbcode(raw: String) -> String:
	var out: String = raw.replace("[[", char(1)).replace("]]", char(2)).replace("[REDACTED]", char(3))
	out = out.replace("[", "[lb]")
	out = out.replace(char(1), "[color=%s]" % _kw_color).replace(char(2), "[/color]")
	var bar: String = _hex("redact")
	out = out.replace(char(3), "[bgcolor=%s][color=%s] REDACTED [/color][/bgcolor]" % [bar, bar])
	return out

func _start_typing() -> void:
	started = true
	enter_lockout_t = ENTER_LOCKOUT
	current_line = 0
	if labels.size() > 0:
		_enter_line(0, false)

# 행 진입 공통 처리 · 정적 행(글자 없음)은 delay만, fast 행은 통째 등장(고속 덤프 ·
# 연속되면 좌라락), 그 외는 타이핑 시작. skip_delay = 사용자 스킵(대기 없이 연쇄).
func _enter_line(i: int, skip_delay: bool) -> void:
	revealed = 0
	t = 0.0
	typing = true
	_reveal_row(i)
	var ln: Dictionary = lines_data[i]
	if _is_static_row(i):
		typing = false
		pause_after_line = 0.0 if skip_delay else float(ln.get("delay", 0.2))
	elif bool(ln.get("fast", false)):
		(labels[i] as RichTextLabel).visible_characters = -1
		typing = false
		pause_after_line = 0.0 if skip_delay else float(ln.get("delay", 0.045))
		_fast_streak += 1
		if _fast_streak % 3 == 1:
			SfxPlayer.play("terminal_typewrite", -6.0)
	else:
		_fast_streak = 0
	_update_scroll_target()

# slow 행(빌드 서명 VEIL) 완성 · 스팅 + 배경이 강조색으로 물든다(한 번 램프 · 점멸 아님,
# 광과민 규칙). 스킵으로 완성해도 한 번은 낸다 · row 메타로 이중 발화 차단.
func _slow_line_done() -> void:
	if current_line < 0 or current_line >= rows.size():
		return
	var row: Control = rows[current_line]
	if row.has_meta("slow_done"):
		return
	row.set_meta("slow_done", true)
	SfxPlayer.play("veil_subtitle_in")
	var tw := bg.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(bg, "color", Color(0.07, 0.03, 0.12, bg.color.a), 0.7)

func _process(delta: float) -> void:
	if done or paper == null or not is_instance_valid(paper):
		return
	# 종이 부드럽게 스크롤 (현재 줄을 화면 중앙 ~40%에 위치) · 고속 덤프 중엔 가속 추적.
	var slerp: float = SCROLL_LERP * (3.5 if _fast_streak > 0 else 1.0)
	paper.position.y = lerp(paper.position.y, paper_target_y, slerp)
	# 페이드인 중엔 typing 진행 X · _start_typing 콜백이 started=true로 바꿔야 시작.
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
		var line: Dictionary = lines_data[current_line]
		t += delta
		if t >= float(line.get("t_int", TYPE_INTERVAL)):
			t = 0.0
			revealed += 1
			var label: RichTextLabel = labels[current_line]
			var total: int = label.get_total_character_count()
			if revealed >= total:
				revealed = total
				label.visible_characters = -1
				typing = false
				pause_after_line = float(line.get("delay", 0.4))
				if bool(line.get("slow", false)):
					_slow_line_done()
			else:
				label.visible_characters = revealed
				if bool(line.get("slow", false)):
					SfxPlayer.play("ui_slider_tick", -2.0)
				else:
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
			_enter_line(current_line, false)

func _update_scroll_target() -> void:
	# 현재 줄의 종이 내부 y 좌표
	if current_line >= rows.size():
		return
	var lbl_y: float = (rows[current_line] as Control).position.y
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
	# 위/아래 hold로 paper_target_y 조정 · 사용자가 다시 읽을 수 있게.
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
	# 페이드인 중 + 진입 직후 마진 · 이전 화면 점프 키 잔여 입력 차단.
	if not started or enter_lockout_t > 0.0:
		return
	# 다 읽힌 상태 · 위/아래는 _process polling, 확인 키는 lockout 후 닫기.
	if reading_done:
		if read_lockout_t > 0.0:
			return
		# 마우스 휠 · 종이 스크롤 (휠 업=위로 거슬러 보기). 사용자: 휠로도 스크롤.
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_scroll_paper(48.0)
				get_viewport().set_input_as_handled()
				return
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_scroll_paper(-48.0)
				get_viewport().set_input_as_handled()
				return
		# 닫기 · 확인 키(Space/Enter)·스킵·공격·좌클릭·화면 탭. jump(W)는 스크롤에 쓰므로 닫기에서 뺀다.
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
		# 현재 줄 즉시 완성 · slow 행(빌드 서명)은 스킵해도 스팅·틴트는 낸다.
		var rl: RichTextLabel = labels[current_line]
		rl.visible_characters = -1
		revealed = rl.get_total_character_count()
		typing = false
		pause_after_line = 0.0
		if bool((lines_data[current_line] as Dictionary).get("slow", false)):
			_slow_line_done()
	else:
		# 다음 줄로 스킵
		current_line += 1
		if current_line >= lines_data.size():
			_enter_reading_done()
			return
		_enter_line(current_line, true)

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

# 터미널 스캔라인 · 4px 주기의 은은한 수평선(CRT 문법). 콘솔 창 위에만 깔린다.
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
