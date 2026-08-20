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
	# 덮어쓰기 한도 세리머니 — 소진 사망(기록 오염)은 재개 지점이 달라지므로 반드시 여기서 고지.
	# 마지막 1회를 쓴 사망에도 다음 실패의 무게를 예고(시스템 브래킷 문법 = 힌트 표기와 통일).
	if not GameState.story_mode and not GameState.playground_active:
		if GameState.overwrite_exhausted:
			full_text += "\n\n[ 기록 덮어쓰기 한도 초과 · 잔존 구간(막 %d 경계)에서 재개 ]" \
				% (GameState.act_for_stage(GameState.current_stage) + 1)
		elif GameState.overwrite_left <= 0:
			full_text += "\n\n[ 덮어쓰기 잔여 0 · 다음 실패는 잔존 구간에서 재개 ]"
	if GameState.story_mode or GameState.playground_active:
		stats_label.text = "사망 횟수  %d  /  도달 스테이지  %d" % [GameState.death_count, GameState.current_stage + 1]
	else:
		stats_label.text = "사망 횟수  %d  /  도달 스테이지  %d  /  기록 덮어쓰기 잔여  %d" \
			% [GameState.death_count, GameState.current_stage + 1, GameState.overwrite_left]
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
	GameState.player_hp = GameState.player_max_hp
	# 한도 소진(기록 오염) — 잔존 구간(막 첫 스테이지) 재개. current_stage 후퇴·저장은
	# register_death가 이미 마쳤고, 여기선 경로만 브리핑으로 바꾼다(루트 재선택 필요).
	if GameState.overwrite_exhausted:
		GameState.overwrite_exhausted = false
		get_tree().change_scene_to_file.call_deferred(SceneRouter.BRIEFING)
		return
	# 14-1 보스전 사망 = 항상 P1부터(2026-08-15 사용자 확정). 사망 경로 한정 —
	# 연습장 페이즈 직행·_init_rival_boss 체크포인트 분기는 그대로 쓴다.
	if GameState.current_route_id == "route_core_recovery":
		GameState.rival_phase_reached = 0
	get_tree().change_scene_to_file.call_deferred(SceneRouter.STAGE)
