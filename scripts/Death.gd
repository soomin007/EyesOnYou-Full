extends Control

@onready var title_label: Label = $Center/V/Title
@onready var speaker_label: Label = $Center/V/Speaker
@onready var text_label: Label = $Center/V/Text
@onready var hint_label: Label = $Center/V/Hint
@onready var stats_label: Label = $Center/V/Stats

const TYPE_INTERVAL: float = 0.05

var full_text: String = ""
var revealed: int = 0
var t: float = 0.0
var done: bool = false
# 진입 직후 1초 입력 lockout · 사망 직전 점프 연타가 다음 화면을 자동 advance하는 사고 방지.
var input_lockout_t: float = GameState.INPUT_LOCKOUT_DURATION
# 오버레이 모드(2026-09-03 · 사망 한 박자 확장) · Stage가 pause로 얼린 죽은 플레이 화면 위에
# 이 씬을 얹는다(Stage._open_death_overlay가 add_child 전에 켠다). 배경을 반투명으로 낮춰
# 정지 장면이 비쳐 보이고, pause는 유지하다가 씬을 떠나는 순간 해제한다.
var overlay_mode: bool = false

func _ready() -> void:
	if overlay_mode:
		# 죽은 장면이 비치는 딤 · 불투명 배경을 낮추고 짧게 차오른다(하드 컷 방지).
		var bg: ColorRect = $BG
		var c: Color = bg.color
		bg.color = Color(c.r, c.g, c.b, 0.0)
		var tw := bg.create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_property(bg, "color:a", 0.62, 0.3)
	else:
		# 안전망: 이전 scene에서 paused가 carry되어 Death가 freeze되는 패턴 차단.
		get_tree().paused = false
	title_label.text = "MISSION FAILED"
	speaker_label.text = "VEIL"
	full_text = VeilDialogue.get_death_briefing(GameState.death_count, GameState.followed_veil_last_choice)
	# 첫 사망에만 다회차 hint · 너무 적극적이지 않게, VEIL 톤으로 슬쩍.
	if GameState.death_count == 1:
		# 어투 밴드 스윕(2026-08-21): 첫 사망 = 사실상 cold 밴드 · 중립 보고체.
		full_text += "\n\n...요원, 다른 결말도 있을지 모릅니다."
	# 재개 지점 고지(2026-08-23 통일) · 사망 = 그 막 첫 스테이지부터. 어디서 다시 서는지는
	# 반드시 화면에 명시(시스템 브래킷 문법). register_death가 이미 후퇴를 마친 뒤라
	# current_stage = 재개 지점이다. 보스전은 같은 자리 처음부터.
	if not GameState.story_mode and not GameState.playground_active:
		if GameState.death_restart_in_place:
			full_text += "\n\n[ 보스전 처음부터 재개 ]"
		else:
			full_text += "\n\n[ 막 %d 첫 구역에서 재개 ]" \
				% (GameState.act_for_stage(GameState.current_stage) + 1)
	stats_label.text = "사망 횟수  %d  /  도달 스테이지  %d" % [GameState.death_count, GameState.current_stage + 1]
	text_label.text = ""
	hint_label.text = ""
	# BGM 그대로 두되 살짝 먹먹하게 · 트랙 전환 없이 -12dB ducking.
	# 재시도 시 stage._ready에서 set_ducked(false)로 복원.
	BgmPlayer.set_ducked(true)
	GameState.input_kind_changed.connect(_on_input_kind_changed)

func _on_input_kind_changed(_kind: String) -> void:
	if done:
		hint_label.text = _done_hint()

func _done_hint() -> String:
	return GameState.hint(
		"[ SPACE  다시 시도 ]   [ ESC  타이틀 ]",
		"[ A  다시 시도 ]   [ B  타이틀 ]")

func _process(delta: float) -> void:
	if input_lockout_t > 0.0:
		input_lockout_t -= delta
	if done:
		return
	t += delta
	if t >= TYPE_INTERVAL:
		t = 0.0
		revealed += 1
		if revealed >= full_text.length():
			revealed = full_text.length()
			done = true
			hint_label.text = _done_hint()
		text_label.text = full_text.substr(0, revealed)

# 모바일: 화면 탭이 UI Control에 먹히기 전에 받으려 _unhandled_input 대신 _input을 쓴다.
func _input(event: InputEvent) -> void:
	if input_lockout_t > 0.0:
		return
	if event.is_action_pressed("ui_cancel"):
		GameState.reset()
		get_tree().paused = false   # 오버레이 모드의 pause 해제(비오버레이에선 이미 false · 무해)
		get_tree().change_scene_to_file.call_deferred(SceneRouter.TITLE)
		return
	if event.is_action_pressed("ui_skip") or event.is_action_pressed("jump") or OrientationGuard.is_tap(event):
		if not done:
			revealed = full_text.length()
			text_label.text = full_text
			done = true
			hint_label.text = _done_hint()
			return
		_restart_stage()

func _restart_stage() -> void:
	get_tree().paused = false   # 오버레이 모드의 pause 해제 · 전환될 새 씬이 얼어 있으면 안 된다
	GameState.player_hp = GameState.effective_max_hp()
	# 스토리 모드·연습장 = 그 스테이지 재시작(쉬운 모드 문법 유지).
	if GameState.story_mode or GameState.playground_active:
		get_tree().change_scene_to_file.call_deferred(SceneRouter.STAGE)
		return
	# 보스전 사망 = 같은 자리 처음부터(14-1은 P1 리셋 · 2026-08-15 확정, SENTINEL(lab)은 08-25).
	# 판정은 register_death가 "죽은 맵" 기준으로 세운 플래그만 본다. current_route_id로 보면 막
	# 되감기 뒤 직전 맵이 lab인 막4 사망이 보스전으로 오인된다(2026-08-29 실사고).
	if GameState.death_restart_in_place:
		if GameState.current_route_id == "route_core_recovery":
			GameState.rival_phase_reached = 0
		get_tree().change_scene_to_file.call_deferred(SceneRouter.STAGE)
		return
	# 본편 사망 = 막 첫 스테이지(2026-08-23 통일). current_stage 후퇴·저장은 register_death가
	# 이미 마쳤고, 여기선 브리핑으로 보낸다(막 첫 구역의 루트 재선택부터).
	get_tree().change_scene_to_file.call_deferred(SceneRouter.BRIEFING)
