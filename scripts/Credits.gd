extends Control

# 크레딧 화면. 두 가지 모드 지원:
#   - standalone scene (game ending → credits → title)
#       set_meta("mode", "scene") 또는 기본값. 끝나면 Title로 이동.
#   - overlay (Settings에서 "크레딧 보기" → 그 자리에서 닫기)
#       open_as_overlay()로 진입. closed signal로 닫힘 알림.
#
# 본 화면은 단순 자동 스크롤 + ESC/뒤로 / SPACE / 클릭으로 종료.

signal closed

# 크레딧 본문. ANNOTATIONS:
#  · [HEADER]   : 큰 글자 (섹션 헤더)
#  · [SUB]      : 회색 작은 글자 (보조)
#  · 빈 줄      : 간격
#  · 그 외      : 본문 18pt
# 마무리에 "감사합니다" 큰 글자 + 페이드.
const CREDITS_LINES: Array[String] = [
	"[HEADER]EYES ON YOU",
	"[SUB]VEIL과 함께하는 임무",
	"",
	"",
	"[HEADER]Direction",
	"Soomin Kim",
	"[SUB]기획 · 총괄 · 창작 방향 · 검수",
	"",
	"",
	"[HEADER]Development & Design",
	"Claude (Anthropic)",
	"[SUB]시스템 설계 · GDScript 구현 · 게임/레벨 디자인",
	"[SUB]VEIL 대사 · 엔딩 · ARCTURUS 단편",
	"[SUB]코드 생성 벡터 그래픽 · UI · 사운드 통합 · 디버깅",
	"[SUB]Soomin Kim의 디렉션 아래 작업",
	"",
	"",
	"[HEADER]Music",
	"Glass Protocol — 메인 테마",
	"Cold Gear — 외곽 / 외벽",
	"Cold Wire — 시설 내부",
	"Chrome Grit — SENTINEL",
	"Gravity Static — ???",
	"Ending A / B / C / D — 결말 분기",
	"[SUB]All tracks generated with Suno",
	"",
	"",
	"[HEADER]Sound Effects",
	"Player · Enemy · Boss · Environment · UI · Story",
	"[SUB]All SFX generated with ElevenLabs",
	"",
	"",
	"[HEADER]Engine",
	"Godot 4.6",
	"[SUB]GL Compatibility · Web Export",
	"",
	"",
	"[HEADER]Font",
	"Pretendard",
	"",
	"",
	"",
	"[BIG]감사합니다",
	"",
	"",
	"[SUB]— END —",
]

const SCROLL_SPEED: float = 36.0   # px / sec
const SCROLL_FAST_MULT: float = 4.0  # SPACE 누르고 있으면 빨리 감기
const TOP_GAP: float = 720.0
const BOTTOM_GAP: float = 240.0

var _is_overlay: bool = false
var _scroll: VBoxContainer
var _scroll_y: float = 0.0
var _content_height: float = 0.0
var _finished: bool = false
var _hint_label: Label
# 진입 직후 입력 lockout — 게임 종료 후 점프 연타가 즉시 크레딧을 닫는 사고 방지.
var _input_lockout_t: float = GameState.INPUT_LOCKOUT_DURATION

# 크레딧 끝 메뉴 (scene 모드). "다시 플레이하기"는 포커스 시 글리치로 글자가 바뀐다.
var _menu_shown: bool = false
var _replay_btn: Button = null
var _morph_tween: Tween = null
const GLITCH_CHARS: String = "▒░█▓◇◆#@%&/\\?ㅁㅇㄹㅂㅈ"
const REPLAY_LABEL: String = "다시 플레이하기"
const REPLAY_LABEL_GLITCH: String = "베일의 진실에 더 다가가기"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 어두운 배경. 오버레이 모드에선 dim, scene 모드에선 솔리드.
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.035, 0.05, 1.0) if not _is_overlay else Color(0, 0, 0, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# 스크롤 컨테이너 — 자식들을 위에서 아래로 쌓고 _scroll_y 만큼 위로 밀어 올림.
	# anchor_preset 없이 절대 좌표만 — VBox는 자식이 추가되며 자동으로 세로로 자란다.
	_scroll = VBoxContainer.new()
	_scroll.add_theme_constant_override("separation", 6)
	_scroll.position = Vector2(0, TOP_GAP)
	# 화면 폭에 맞춤 — 라인은 SIZE_EXPAND_FILL+CENTER라 화면 가로 중앙 정렬(적응형).
	_scroll.size = Vector2(get_viewport().get_visible_rect().size.x, 0)
	_scroll.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_scroll)
	_build_lines()
	# 안내 — 우하단. ESC/뒤로 = 즉시 종료, SPACE 길게 = 빨리 감기 (overlay/scene 동일).
	_hint_label = Label.new()
	_hint_label.text = _hint_text()
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint_label.size = Vector2(300, 18)
	_hint_label.position = Vector2(-300.0 - 20.0, -18.0 - 16.0)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_hint_label)
	GameState.input_kind_changed.connect(_on_input_kind_changed)
	# scene 모드 진입에서도 main_theme이 부드럽게 이어지도록 (이미 같은 트랙이면 무시됨).
	BgmPlayer.play("main_theme")

func _on_input_kind_changed(_kind: String) -> void:
	if is_instance_valid(_hint_label):
		_hint_label.text = _hint_text()

func _hint_text() -> String:
	return GameState.hint(
		"SPACE 빨리 감기 · ESC 닫기",
		"A 빨리 감기 · B 닫기")

func _build_lines() -> void:
	for raw in CREDITS_LINES:
		var line: String = raw
		var l := Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if line.begins_with("[HEADER]"):
			l.text = line.substr("[HEADER]".length())
			l.add_theme_font_size_override("font_size", 26)
			l.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
		elif line.begins_with("[SUB]"):
			l.text = line.substr("[SUB]".length())
			l.add_theme_font_size_override("font_size", 14)
			l.add_theme_color_override("font_color", Color(0.55, 0.62, 0.72))
		elif line.begins_with("[BIG]"):
			l.text = line.substr("[BIG]".length())
			l.add_theme_font_size_override("font_size", 36)
			l.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
		elif line.is_empty():
			l.custom_minimum_size = Vector2(0, 14)
		else:
			l.text = line
			l.add_theme_font_size_override("font_size", 18)
			l.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
		_scroll.add_child(l)
	# 컨테이너의 정확한 높이는 layout 후에야 계산됨. 다음 프레임에 측정.
	call_deferred("_measure_content")

func _measure_content() -> void:
	_content_height = _scroll.size.y

func _process(delta: float) -> void:
	if _input_lockout_t > 0.0:
		_input_lockout_t -= delta
	if _finished or _menu_shown:
		return
	var speed: float = SCROLL_SPEED
	if Input.is_action_pressed("ui_skip") or Input.is_action_pressed("jump") or Input.is_action_pressed("ui_accept"):
		speed *= SCROLL_FAST_MULT
	_scroll_y += speed * delta
	_scroll.position.y = TOP_GAP - _scroll_y
	# 끝까지 올라가면 — scene 모드: 다시 플레이/나가기 메뉴. overlay 모드: 그냥 닫기.
	if _content_height > 0.0 and _scroll_y >= _content_height + BOTTOM_GAP:
		if _is_overlay:
			_finish(true)
		else:
			_show_end_menu()

func _unhandled_input(event: InputEvent) -> void:
	# ESC는 최우선 — 입력 락아웃과 무관하게 즉시 반응(락아웃은 점프 연타 차단용이라 ESC엔 불필요).
	if event.is_action_pressed("ui_cancel"):
		if _is_overlay:
			# 오버레이 — 짧게 페이드 후 닫기.
			_finish(false)
		elif not _menu_shown:
			# scene 모드 스크롤 중 ESC — 끝까지 기다리지 않고 바로 메뉴로.
			_show_end_menu()
		else:
			# 메뉴에서 ESC — 메인으로.
			_on_exit_pressed()
		get_viewport().set_input_as_handled()
		return
	if _input_lockout_t > 0.0:
		return

# fade_long=true — 자동 종료(긴 1.5s 페이드, 여운). false — 수동 ESC(짧은 0.3s).
func _finish(fade_long: bool) -> void:
	if _finished:
		return
	_finished = true
	var fade_dur: float = 1.5 if fade_long else 0.3
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, fade_dur)
	tw.tween_callback(_actually_finish)

func _actually_finish() -> void:
	if _is_overlay:
		emit_signal("closed")
		return
	# scene 모드 — 타이틀로.
	GameState.reset()
	get_tree().change_scene_to_file(SceneRouter.TITLE)

# Settings에서 호출. closed 시그널을 듣고 부모가 free하면 됨.
func open_as_overlay() -> void:
	_is_overlay = true

# ─── 크레딧 끝 메뉴 (scene 모드) ──────────────────────────────────
# "다시 플레이하기" = 명시적 다회차 신호(GameState.replaying). 물음표 방 첫 단말기가
# VEIL-1 대신 추가 풀로 변형된다(부스 기기≠사람 문제 회피). 포커스 시 글자가 글리치로
# "베일의 진실에 더 다가가기"로 치직거리며 바뀐다.
func _show_end_menu() -> void:
	if _menu_shown:
		return
	_menu_shown = true
	if is_instance_valid(_hint_label):
		_hint_label.visible = false
	# 스크롤 중 ESC로 메뉴를 띄우면 _process가 _menu_shown에서 멈춰 크레딧 본문이 그 자리에
	# 정지 → 메뉴 버튼과 겹친다(끝까지 자동 스크롤된 경우엔 위로 올라가 안 보임). 본문을 숨겨 분리.
	if is_instance_valid(_scroll):
		_scroll.visible = false
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 20)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vb)
	_replay_btn = _make_credit_button(REPLAY_LABEL)
	_replay_btn.pressed.connect(_on_replay_pressed)
	_replay_btn.focus_entered.connect(_on_replay_focus)
	_replay_btn.focus_exited.connect(_on_replay_unfocus)
	_replay_btn.mouse_entered.connect(_on_replay_focus)
	_replay_btn.mouse_exited.connect(_on_replay_unfocus)
	vb.add_child(_replay_btn)
	var feedback_btn := _make_credit_button("피드백 보내기")
	feedback_btn.pressed.connect(_on_feedback_pressed)
	vb.add_child(feedback_btn)
	var exit_btn := _make_credit_button("메인 화면으로 나가기")
	exit_btn.pressed.connect(_on_exit_pressed)
	vb.add_child(exit_btn)
	center.modulate.a = 0.0
	center.create_tween().tween_property(center, "modulate:a", 1.0, 0.6)
	# 잠깐 "다시 플레이하기"를 보여준 뒤(0.6s) 포커스 → 그 순간 글리치로 변형.
	GameState.arm_focus_with_delay(self, _replay_btn, 0.6)

func _make_credit_button(label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.add_theme_font_size_override("font_size", 22)
	b.custom_minimum_size = Vector2(480, 54)
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	return b

func _on_replay_focus() -> void:
	_glitch_morph(_replay_btn, REPLAY_LABEL_GLITCH)

func _on_replay_unfocus() -> void:
	# 포커스도 마우스도 없을 때만 원래 글자로 — 한쪽이라도 걸려 있으면 글리치 라벨 유지.
	if is_instance_valid(_replay_btn) and not _replay_btn.has_focus():
		_glitch_morph(_replay_btn, REPLAY_LABEL)

# 글자가 글리치 문자로 흩어졌다 목표 텍스트로 수렴 (~0.3s). reveal 0→1로 점점 또렷해진다.
func _glitch_morph(btn: Button, target: String) -> void:
	if not is_instance_valid(btn):
		return
	if _morph_tween != null and _morph_tween.is_valid():
		_morph_tween.kill()
	_morph_tween = btn.create_tween()
	_morph_tween.tween_method(func(r: float) -> void:
		if is_instance_valid(btn):
			btn.text = _scramble(target, r)
	, 0.0, 1.0, 0.30)
	_morph_tween.tween_callback(func() -> void:
		if is_instance_valid(btn):
			btn.text = target)

func _scramble(target: String, reveal: float) -> String:
	var out: String = ""
	for i in target.length():
		var ch: String = target[i]
		if ch == " ":
			out += ch
		elif randf() < reveal:
			out += ch
		else:
			out += GLITCH_CHARS[randi() % GLITCH_CHARS.length()]
	return out

func _on_replay_pressed() -> void:
	# 명시적 다회차 — 물음표 변형 활성. 새 런(노멀) 시작.
	GameState.replaying = true
	GameState.reset()
	get_tree().change_scene_to_file(SceneRouter.BRIEFING)

func _on_feedback_pressed() -> void:
	GameState.open_feedback()

func _on_exit_pressed() -> void:
	GameState.replaying = false
	GameState.reset()
	get_tree().change_scene_to_file(SceneRouter.TITLE)
