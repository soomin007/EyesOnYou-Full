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
# 진입 직후 1초 입력 lockout — 사망 직전 점프 연타가 다음 화면을 자동 advance하는 사고 방지.
var input_lockout_t: float = GameState.INPUT_LOCKOUT_DURATION

func _ready() -> void:
	# 안전망: 이전 scene에서 paused가 carry되어 Death가 freeze되는 패턴 차단.
	get_tree().paused = false
	title_label.text = "MISSION FAILED"
	speaker_label.text = "VEIL"
	full_text = VeilDialogue.get_death_briefing(GameState.death_count, GameState.followed_veil_last_choice)
	# 첫 사망에만 다회차 hint — 너무 적극적이지 않게, VEIL 톤으로 슬쩍.
	if GameState.death_count == 1:
		full_text += "\n\n...요원, 다른 결말도 있을지 몰라요."
	stats_label.text = "사망 횟수  %d  /  도달 스테이지  %d" % [GameState.death_count, GameState.current_stage + 1]
	text_label.text = ""
	hint_label.text = ""
	# BGM 그대로 두되 살짝 먹먹하게 — 트랙 전환 없이 -12dB ducking.
	# 재시도 시 stage._ready에서 set_ducked(false)로 복원.
	BgmPlayer.set_ducked(true)
	GameState.input_kind_changed.connect(_on_input_kind_changed)

func _on_input_kind_changed(_kind: String) -> void:
	if done:
		hint_label.text = _done_hint()

func _done_hint() -> String:
	return GameState.hint(
		"[ SPACE — 다시 시도 ]   [ ESC — 타이틀 ]",
		"[ A — 다시 시도 ]   [ B — 타이틀 ]")

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

func _unhandled_input(event: InputEvent) -> void:
	if input_lockout_t > 0.0:
		return
	if event.is_action_pressed("ui_cancel"):
		GameState.reset()
		get_tree().change_scene_to_file(SceneRouter.TITLE)
		return
	if event.is_action_pressed("ui_skip") or event.is_action_pressed("jump"):
		if not done:
			revealed = full_text.length()
			text_label.text = full_text
			done = true
			hint_label.text = _done_hint()
			return
		_restart_stage()

func _restart_stage() -> void:
	GameState.player_hp = GameState.player_max_hp
	get_tree().change_scene_to_file(SceneRouter.STAGE)
